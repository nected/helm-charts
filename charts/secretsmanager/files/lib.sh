# Shared helpers. Sourced by run.sh; no shebang, not executable on its own.
#
# Deliberately dependency-free: the job image provides openssl, busybox wget,
# kubectl, sed and awk, and nothing else is assumed. That is why there is a
# hand-written JSON reader below instead of jq.

# Everything diagnostic goes to stderr, on one stream so the log reads in the
# order things happened. stdout carries secret VALUES only - a provider_get is
# captured by its caller, so a stray note there would be written into the
# payload instead of the log.
warn() { echo "WARNING: $*" >&2; }
note() { echo "$*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ---------- encoding ----------

# Raw bytes on stdin -> lowercase hex. od rather than xxd so this works on any
# busybox build.
to_hex() { od -An -v -tx1 | tr -d ' \n'; }

sha256_hex() { openssl dgst -sha256 -binary | to_hex; }

# HMAC-SHA256 keyed with hex, emitting hex. Chained to build signing keys.
hmac_hex() { openssl dgst -sha256 -mac HMAC -macopt "hexkey:$1" -binary | to_hex; }

# Percent-encode everything outside the unreserved set, for form bodies.
url_encode() {
  printf '%s' "$1" | od -An -v -tx1 | tr ' ' '\n' | grep -v '^$' | awk '
    BEGIN { for (i = 0; i < 256; i++) ord[sprintf("%02x", i)] = i }
    {
      c = ord[$1]
      if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
          c == 45 || c == 46 || c == 95 || c == 126)
        printf "%c", c
      else
        printf "%%%s", toupper($1)
    }'
}

# A v4 UUID. The kernel source is present on every Linux the job runs on;
# the openssl fallback keeps this working if /proc is not mounted.
new_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
    return 0
  fi
  _h=$(openssl rand -hex 16)
  printf '%s-%s-4%s-a%s-%s' \
    "$(printf '%s' "$_h" | cut -c1-8)"  "$(printf '%s' "$_h" | cut -c9-12)" \
    "$(printf '%s' "$_h" | cut -c14-16)" "$(printf '%s' "$_h" | cut -c18-20)" \
    "$(printf '%s' "$_h" | cut -c21-32)"
}

# ---------- tiny readers ----------
# xml_field only has to handle the fixed shape STS returns. JSON goes through
# json_one, which decodes escapes properly.

xml_field()  { tr -d '\n' | sed -n "s|.*<$1>\([^<]*\)</$1>.*|\1|p" | head -1; }

# ---------- JSON ----------
# Both delegate to json.awk, which lives beside this file in the ConfigMap.

LIB_DIR="${LIB_DIR:-$(dirname "$0")}"

# Reads a flat JSON object on stdin, writing each string value to <dir>/<KEY>.
# Files rather than --from-literal so values never reach the process list and
# may contain any byte. Prints the key count; non-zero on malformed input.
json_to_files() { awk -v mode=files -v dir="$1" -f "$LIB_DIR/json.awk"; }

# Prints one key's decoded value. Returns 2 if the key is absent. Handles the
# escaped-JSON-inside-JSON that provider responses use.
json_one() { awk -v mode=one -v key="$1" -f "$LIB_DIR/json.awk"; }

# ---------- kubernetes ----------

HASH_ANNOTATION="nected.ai/payload-hash"

# Scratch space for intermediate manifests; run.sh points this at its work dir.
WORK_TMP="${WORK_TMP:-/tmp}"

k8s_secret_hash() {
  kubectl get secret "$1" -o "jsonpath={.metadata.annotations['nected\.ai/payload-hash']}" 2>/dev/null
}

k8s_secret_exists() { kubectl get secret "$1" >/dev/null 2>&1; }

# Create or replace a Secret from a directory of files, one per key.
#
# Each stage is run separately rather than as one pipeline: a pipeline reports
# only the last command's status, so a failure in create or annotate was
# invisible and surfaced as an unexplained "could not write Secret".
k8s_apply_secret_from_dir() {
  _name="$1"; _dir="$2"; _hash="$3"
  _m1="$WORK_TMP/manifest.1"; _m2="$WORK_TMP/manifest.2"; _err="$WORK_TMP/kubectl.err"

  if ! kubectl create secret generic "$_name" --from-file="$_dir" \
         --dry-run=client -o yaml > "$_m1" 2>"$_err"; then
    warn "building the Secret manifest failed:"; sed 's/^/    /' "$_err" >&2
    return 1
  fi
  if ! kubectl annotate --local -f "$_m1" "${HASH_ANNOTATION}=${_hash}" \
         --dry-run=client -o yaml > "$_m2" 2>"$_err"; then
    warn "annotating the Secret manifest failed:"; sed 's/^/    /' "$_err" >&2
    return 1
  fi
  if ! kubectl apply -f "$_m2" >/dev/null 2>"$_err"; then
    warn "applying the Secret failed:"; sed 's/^/    /' "$_err" >&2
    return 1
  fi
  return 0
}

# Values from envFrom/secretKeyRef are fixed when a container starts, so a
# rotated Secret stays invisible until pods are replaced.
k8s_restart() {
  for _d in $1; do
    if kubectl patch deployment "$_d" \
         -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"${HASH_ANNOTATION}\":\"$2\"}}}}}" \
         >/dev/null 2>&1; then
      note "  restarted Deployment/$_d"
    else
      # Absent on a first install: the Deployment does not exist yet when the
      # pre-install hook runs, and new pods read the Secret anyway.
      note "  Deployment/$_d not present yet; skipping"
    fi
  done
}
