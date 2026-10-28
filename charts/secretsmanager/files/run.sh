#!/bin/sh
# secretsmanager: materialise Kubernetes Secrets from a cloud secret manager,
# and back the encryption-at-rest key up to it.
#
# Runs as a pre-install/pre-upgrade hook ahead of the temporal and nected
# releases. Idempotent: an unchanged payload writes nothing and restarts
# nothing, so running it on every upgrade is free.
#
# Config arrives as environment variables rendered by the chart.

set -u

LIB_DIR="$(dirname "$0")"
export LIB_DIR
. "$LIB_DIR/lib.sh"
. "$LIB_DIR/http.sh"

PROVIDER="${PROVIDER:-}"
FAIL_OPEN="${FAIL_OPEN:-true}"

# Credentials sync
CRED_SECRET="${CRED_SECRET:-}"
CRED_REMOTE_KEYS="${CRED_REMOTE_KEYS:-}"
CRED_REQUIRED_KEYS="${CRED_REQUIRED_KEYS:-}"
# Space-separated TARGET=SOURCE pairs: copy one fetched value to a second key.
CRED_ALIASES="${CRED_ALIASES:-}"
RESTART_TARGETS="${RESTART_TARGETS:-}"

# Encryption-at-rest key
EAR_SECRET="${EAR_SECRET:-encryption-at-rest-secret}"
EAR_KEY="${EAR_KEY:-encryption-at-rest}"
EAR_REMOTE="${EAR_REMOTE:-}"
EAR_MANAGE="${EAR_MANAGE:-false}"
EAR_BACKUP="${EAR_BACKUP:-false}"
EAR_OVERWRITE="${EAR_OVERWRITE:-false}"

WORK="/tmp/secretsmanager.$$"
trap 'rm -rf "$WORK"; http_cleanup' EXIT INT TERM
mkdir -p "$WORK" || die "cannot create a work directory"
WORK_TMP="$WORK"
export WORK_TMP

case "$PROVIDER" in
  aws)   . "$LIB_DIR/aws.sh" ;;
  azure) . "$LIB_DIR/azure.sh" ;;
  *)     die "PROVIDER must be aws or azure (got '${PROVIDER}')" ;;
esac

# A provider problem must not break a release when the cluster already holds
# usable Secrets. A first install has nothing to fall back on, so it fails.
have_usable_fallback() {
  [ -n "$CRED_SECRET" ] || return 0
  k8s_secret_exists "$CRED_SECRET"
}

bail_or_continue() {
  if [ "$FAIL_OPEN" = "true" ] && have_usable_fallback; then
    warn "$1"
    warn "failOpen is set and the existing Secrets are still in place; continuing."
    exit 0
  fi
  die "$1"
}

note "secretsmanager: provider $(provider_name)"
provider_init || bail_or_continue "could not initialise $(provider_name)"

# ---------------------------------------------------------------------------
# 1. Encryption-at-rest key
#
# Restore it from the vault if present, otherwise generate it. Doing this here
# rather than in the nected chart means generation and backup sit in one job,
# so there is no ordering knot between them. The nected chart's own job guards
# on existence, so it simply no-ops afterwards.
# ---------------------------------------------------------------------------
ear_sync() {
  [ "$EAR_MANAGE" = "true" ] || return 0
  note "encryption-at-rest key:"

  if k8s_secret_exists "$EAR_SECRET"; then
    note "  Secret '$EAR_SECRET' already present"
  else
    _restored=0
    if [ -n "$EAR_REMOTE" ]; then
      if provider_get "$EAR_REMOTE" > "$WORK/ear.b64" && [ -s "$WORK/ear.b64" ]; then
        note "  restoring from '$EAR_REMOTE'"
        if base64 -d < "$WORK/ear.b64" > "$WORK/$EAR_KEY" 2>/dev/null && [ -s "$WORK/$EAR_KEY" ]; then
          kubectl create secret generic "$EAR_SECRET" --from-file="$WORK/$EAR_KEY" >/dev/null 2>&1 \
            && { note "  restored"; _restored=1; } \
            || warn "  could not create '$EAR_SECRET' from the restored key"
        else
          warn "  the stored value is not valid base64; not restoring"
        fi
      fi
    fi

    if [ "$_restored" -eq 0 ]; then
      note "  generating a new RSA key"
      openssl genrsa -f4 -out "$WORK/$EAR_KEY" 4096 >/dev/null 2>&1 \
        || die "could not generate the encryption-at-rest key"
      kubectl create secret generic "$EAR_SECRET" --from-file="$WORK/$EAR_KEY" >/dev/null 2>&1 \
        || die "could not create Secret '$EAR_SECRET'"
      note "  generated"
    fi
  fi

  # Back it up. The Secret's .data value is already base64, which is exactly
  # what gets stored, so the key is never written to disk in the clear and a
  # restore is a copy-paste into commonSecret.secretValue.
  if [ "$EAR_BACKUP" = "true" ] && [ -n "$EAR_REMOTE" ]; then
    _b64=$(kubectl get secret "$EAR_SECRET" -o "jsonpath={.data['${EAR_KEY}']}" 2>/dev/null)
    if [ -z "$_b64" ]; then
      warn "  could not read the key back; skipping backup"
      return 0
    fi
    printf '%s' "$_b64" > "$WORK/ear.push"
    if provider_exists "$EAR_REMOTE"; then
      if [ "$EAR_OVERWRITE" = "true" ]; then
        provider_update "$EAR_REMOTE" "$WORK/ear.push" && note "  backup updated" \
          || warn "  could not update the backup; continuing"
      else
        # Overwriting is destructive: if another cluster stored its own key
        # here, replacing it discards the only off-cluster copy of a key that
        # may still decrypt live data.
        note "  '$EAR_REMOTE' already holds a value; leaving it untouched"
        note "  (set earKey.overwrite=true to replace it)"
      fi
    else
      provider_create "$EAR_REMOTE" "$WORK/ear.push" && note "  backup created" \
        || warn "  could not create the backup; continuing"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 2. Application credentials
#
# Several remote items are merged in order, later winning, so values with
# different rotation rules can live apart in the vault and still land in one
# Secret.
# ---------------------------------------------------------------------------
creds_sync() {
  [ -n "$CRED_SECRET" ] || return 0
  [ -n "$CRED_REMOTE_KEYS" ] || return 0
  note "credentials -> Secret '$CRED_SECRET':"

  _dir="$WORK/data"; mkdir -p "$_dir"
  _found=0
  for _rk in $CRED_REMOTE_KEYS; do
    if provider_get "$_rk" > "$WORK/blob"; then
      _n=$(json_to_files "$_dir" < "$WORK/blob" 2>"$WORK/jerr") || {
        warn "  '$_rk' is not a flat JSON object of strings:"
        sed 's/^/    /' "$WORK/jerr" >&2
        bail_or_continue "refusing to write a partial Secret from '$_rk'"
      }
      note "  $_rk: $_n keys"
      _found=$((_found+1))
    else
      _rc=$?
      if [ "$_rc" -eq 2 ]; then
        bail_or_continue "remote item '$_rk' does not exist"
      else
        bail_or_continue "could not read remote item '$_rk'"
      fi
    fi
  done
  [ "$_found" -gt 0 ] || { warn "  no remote item resolved; nothing to do"; return 0; }

  # Aliases: let one stored value serve two env vars, so a rotation touches
  # the vault once. Applied after the merge and before validation and hashing,
  # so an alias target can appear in requiredKeys and is covered by the hash.
  for _pair in $CRED_ALIASES; do
    _target=${_pair%%=*}
    _source=${_pair#*=}
    if [ "$_target" = "$_pair" ] || [ -z "$_source" ] || [ -z "$_target" ]; then
      bail_or_continue "malformed alias '$_pair' (expected TARGET=SOURCE)"
      continue
    fi
    if [ ! -f "$_dir/$_source" ]; then
      bail_or_continue "alias $_target=$_source: no key '$_source' in the merged payload"
      continue
    fi
    if [ -f "$_dir/$_target" ]; then
      if cmp -s "$_dir/$_target" "$_dir/$_source"; then
        note "  alias $_target=$_source: already identical in the vault; left alone"
      else
        # The stored value is explicit, a derived copy is not - so the vault
        # wins and the mismatch is surfaced rather than silently overwritten.
        warn "  alias $_target=$_source: '$_target' is already set to a DIFFERENT value;"
        warn "  keeping the stored one. Remove it from the vault or drop the alias."
      fi
      continue
    fi
    cp "$_dir/$_source" "$_dir/$_target"
    note "  alias $_target=$_source"
  done

  # Validate before writing, so a malformed payload never reaches a running
  # system half-applied.
  _missing=""
  for _k in $CRED_REQUIRED_KEYS; do
    [ -s "$_dir/$_k" ] || _missing="$_missing $_k"
  done
  if [ -n "$_missing" ]; then
    bail_or_continue "merged payload is missing required keys:$_missing"
  fi

  # Order-independent digest: key order must not look like a change, or every
  # run would roll the fleet.
  _hash=$(for _f in $(ls "$_dir" | sort); do
            printf '%s=' "$_f"; cat "$_dir/$_f"; printf '\000'
          done | sha256_hex)

  _cur=$(k8s_secret_hash "$CRED_SECRET")
  if [ "$_cur" = "$_hash" ]; then
    note "  unchanged ($(ls "$_dir" | wc -l | tr -d ' ') keys); nothing written"
    return 0
  fi

  k8s_apply_secret_from_dir "$CRED_SECRET" "$_dir" "$_hash" \
    || die "could not write Secret '$CRED_SECRET'"
  note "  updated ($(ls "$_dir" | wc -l | tr -d ' ') keys)"

  if [ -n "$RESTART_TARGETS" ]; then
    note "  rolling consumers (env values are fixed at container start):"
    k8s_restart "$RESTART_TARGETS" "$(printf '%s' "$_hash" | cut -c1-32)"
  else
    warn "  no restart targets configured; running pods keep the previous values"
  fi
}

ear_sync
creds_sync
note "done."
exit 0
