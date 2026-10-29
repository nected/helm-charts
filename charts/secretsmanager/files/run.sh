#!/bin/sh
# secretsmanager: the one job that materialises Nected's Kubernetes Secrets.
#
# Runs as a pre-install/pre-upgrade hook ahead of everything else in its
# release. Two independent pieces of work:
#
#   commonSecret  ensure the encryption-at-rest key exists
#   credentials   read the application credentials into a Secret
#
# PROVIDER selects the vault, it does not switch the job on. With no provider
# the encryption-at-rest key is still generated locally, which is what the
# nected chart's own job used to do.
#
# Idempotent: an unchanged payload writes nothing and restarts nothing.

set -u

LIB_DIR="$(dirname "$0")"
. "$LIB_DIR/lib.sh"

PROVIDER="${PROVIDER:-}"
FAIL_OPEN="${FAIL_OPEN:-true}"

# commonSecret - the encryption-at-rest key
EAR_ENABLED="${EAR_ENABLED:-false}"
EAR_SECRET="${EAR_SECRET:-encryption-at-rest-secret}"
EAR_KEY="${EAR_KEY:-encryption-at-rest}"
EAR_VALUE="${EAR_VALUE:-}"
EAR_REMOTE="${EAR_REMOTE:-}"
EAR_BACKUP="${EAR_BACKUP:-false}"
EAR_OVERWRITE="${EAR_OVERWRITE:-false}"

# credentials
CRED_SECRET="${CRED_SECRET:-}"
CRED_REMOTE_KEYS="${CRED_REMOTE_KEYS:-}"
CRED_REQUIRED_KEYS="${CRED_REQUIRED_KEYS:-}"
CRED_ALIASES="${CRED_ALIASES:-}"
RESTART_TARGETS="${RESTART_TARGETS:-}"

require_tools

WORK="/tmp/secretsmanager.$$"
trap 'rm -rf "$WORK"; http_cleanup' EXIT INT TERM
mkdir -p "$WORK" || die "cannot create a work directory"

HAVE_PROVIDER=0
case "$PROVIDER" in
  "")          ;;
  aws|azure)   . "$LIB_DIR/${PROVIDER}.sh"; HAVE_PROVIDER=1 ;;
  *)           die "PROVIDER must be empty, aws or azure (got '$PROVIDER')" ;;
esac

[ -n "$CRED_SECRET" ] && [ "$HAVE_PROVIDER" -eq 0 ] \
  && die "credentials need a provider: set provider to aws or azure"

# A provider problem must not break a release when the cluster already holds a
# usable Secret. A first install has nothing to fall back on, so it fails.
bail_or_continue() {
  if [ "$FAIL_OPEN" = "true" ] && [ -n "$CRED_SECRET" ] && k8s_secret_exists "$CRED_SECRET"; then
    warn "$1"
    warn "failOpen is set and the existing Secret is still in place; continuing."
    exit 0
  fi
  die "$1"
}

if [ "$HAVE_PROVIDER" -eq 1 ]; then
  note "secretsmanager: provider $(provider_name)"
  provider_init || bail_or_continue "could not initialise $(provider_name)"
else
  note "secretsmanager: no provider configured (local mode)"
fi

# ---------------------------------------------------------------------------
# Encryption-at-rest key
#
# Precedence, highest first:
#   1. the Secret already exists      - never touched, so data stays readable
#   2. commonSecret.secretValue       - an operator's deliberate restore
#   3. the vault                      - automatic recovery after a cluster loss
#   4. generate                       - first install
# then push a copy to the vault when a provider and remoteKey are configured.
# ---------------------------------------------------------------------------
ear_sync() {
  [ "$EAR_ENABLED" = "true" ] || return 0
  note "encryption-at-rest key:"

  if k8s_secret_exists "$EAR_SECRET"; then
    note "  Secret '$EAR_SECRET' already present"
  else
    _b64=""
    _from=""

    if [ -n "$EAR_VALUE" ]; then
      _b64="$EAR_VALUE"; _from="commonSecret.secretValue"
      [ "$HAVE_PROVIDER" -eq 1 ] && [ -n "$EAR_REMOTE" ] \
        && warn "  secretValue is set, so the vault copy of '$EAR_REMOTE' is NOT used"
    elif [ "$HAVE_PROVIDER" -eq 1 ] && [ -n "$EAR_REMOTE" ]; then
      if _v=$(provider_get "$EAR_REMOTE" 2>/dev/null) && [ -n "$_v" ]; then
        _b64="$_v"; _from="the vault item '$EAR_REMOTE'"
      fi
    fi

    if [ -n "$_b64" ]; then
      note "  restoring from $_from"
      if ! printf '%s' "$_b64" | base64 -d > "$WORK/$EAR_KEY" 2>/dev/null || [ ! -s "$WORK/$EAR_KEY" ]; then
        die "the value from $_from is not valid base64; refusing to create a broken key"
      fi
    else
      note "  generating a new RSA key"
      openssl genrsa -f4 -out "$WORK/$EAR_KEY" 4096 >/dev/null 2>&1 \
        || die "could not generate the encryption-at-rest key"
    fi

    kubectl create secret generic "$EAR_SECRET" --from-file="$WORK/$EAR_KEY" >/dev/null 2>&1 \
      || die "could not create Secret '$EAR_SECRET'"
    note "  created"
  fi

  # Back it up. The Secret's .data value is already base64, which is exactly
  # what gets stored - so the key is never written to disk in the clear and a
  # restore is a paste into commonSecret.secretValue.
  { [ "$EAR_BACKUP" = "true" ] && [ "$HAVE_PROVIDER" -eq 1 ] && [ -n "$EAR_REMOTE" ]; } || return 0

  _cur=$(k8s_secret_value_b64 "$EAR_SECRET" "$EAR_KEY")
  if [ -z "$_cur" ]; then
    warn "  could not read the key back; skipping backup"
    return 0
  fi
  printf '%s' "$_cur" > "$WORK/ear.push"

  if provider_exists "$EAR_REMOTE"; then
    if [ "$EAR_OVERWRITE" = "true" ]; then
      provider_update "$EAR_REMOTE" "$WORK/ear.push" && note "  backup updated" \
        || warn "  could not update the backup; continuing"
    else
      # Overwriting is destructive: if another cluster stored its own key here,
      # replacing it discards the only off-cluster copy of a key that may still
      # decrypt live data.
      note "  '$EAR_REMOTE' already holds a value; leaving it untouched"
      note "  (set commonSecret.overwrite=true to replace it)"
    fi
  else
    provider_create "$EAR_REMOTE" "$WORK/ear.push" && note "  backup created" \
      || warn "  could not create the backup; continuing"
  fi
}

# ---------------------------------------------------------------------------
# Application credentials
# ---------------------------------------------------------------------------
creds_sync() {
  { [ -n "$CRED_SECRET" ] && [ -n "$CRED_REMOTE_KEYS" ]; } || return 0
  note "credentials -> Secret '$CRED_SECRET':"

  _dir="$WORK/data"; mkdir -p "$_dir"
  _found=0
  for _rk in $CRED_REMOTE_KEYS; do
    if provider_get "$_rk" > "$WORK/blob"; then
      _n=$(json_to_files "$_dir" < "$WORK/blob") || {
        bail_or_continue "refusing to write a partial Secret from '$_rk'"
      }
      note "  $_rk: $_n keys"
      _found=$((_found + 1))
    else
      [ $? -eq 2 ] && bail_or_continue "remote item '$_rk' does not exist" \
                   || bail_or_continue "could not read remote item '$_rk'"
    fi
  done
  [ "$_found" -gt 0 ] || { warn "  no remote item resolved; nothing to do"; return 0; }

  # Aliases let one stored value serve two env vars, so a rotation touches the
  # vault once. Applied before validation and hashing, so a target can appear
  # in requiredKeys and is covered by the hash.
  for _pair in $CRED_ALIASES; do
    _target=${_pair%%=*}; _source=${_pair#*=}
    { [ "$_target" != "$_pair" ] && [ -n "$_source" ] && [ -n "$_target" ]; } \
      || { bail_or_continue "malformed alias '$_pair' (expected TARGET=SOURCE)"; continue; }
    [ -f "$_dir/$_source" ] \
      || { bail_or_continue "alias $_target=$_source: no key '$_source' in the merged payload"; continue; }
    if [ -f "$_dir/$_target" ]; then
      if cmp -s "$_dir/$_target" "$_dir/$_source"; then
        note "  alias $_target=$_source: already identical in the vault; left alone"
      else
        # An explicit stored value beats a derived copy.
        warn "  alias $_target=$_source: '$_target' already holds a DIFFERENT value;"
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
  [ -z "$_missing" ] || bail_or_continue "merged payload is missing required keys:$_missing"

  # Order-independent digest: key order must not look like a change, or every
  # run would roll the fleet.
  _hash=$(for _f in $(ls "$_dir" | sort); do
            printf '%s=' "$_f"; cat "$_dir/$_f"; printf '\000'
          done | openssl dgst -sha256 -binary | od -An -v -tx1 | tr -d ' \n')

  if [ "$(k8s_secret_hash "$CRED_SECRET")" = "$_hash" ]; then
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
