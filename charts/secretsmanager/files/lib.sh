# Shared helpers. Sourced by run.sh; not executable on its own.
#
# The job image must provide curl, jq, kubectl and openssl. require_tools
# checks that up front: a missing tool is a clear failure rather than a
# confusing one halfway through.

warn() { echo "WARNING: $*" >&2; }
note() { echo "$*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

require_tools() {
  for _t in curl jq kubectl openssl; do
    command -v "$_t" >/dev/null 2>&1 \
      || die "the job image must provide '$_t'. Use an image built from devops/openssl-docker."
  done
}

# A v4 UUID. CreateSecret and PutSecretValue require a ClientRequestToken,
# which the AWS SDKs generate automatically but a raw API caller must supply.
new_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{3})(.{3})(.{12})/\1-\2-4\3-a\4-\5/'
  fi
}

# ---------- HTTP ----------
#
# curl, not wget: busybox wget discards the response body on a 4xx, which makes
# every provider error indistinguishable - no AccessDenied vs ResourceNotFound,
# no message. curl keeps it, reports the real status, verifies TLS by default
# and speaks every method.

HTTP_BODY="/tmp/.http_body.$$"
HTTP_STATUS_FILE="/tmp/.http_status.$$"

http_cleanup() { rm -f "$HTTP_BODY" "$HTTP_STATUS_FILE"; }

# Callers run http_send inside command substitution, so the status has to
# cross a subshell boundary.
http_status() { cat "$HTTP_STATUS_FILE" 2>/dev/null || echo "?"; }

# http_send METHOD URL BODY-FILE-OR-EMPTY [curl-arg ...]
# Body on stdout, status via http_status. Returns 0 only for a 2xx.
http_send() {
  _method="$1"; _url="$2"; _body="$3"; shift 3
  set -- "$@" -sS -m 30 -X "$_method" -o "$HTTP_BODY" -w '%{http_code}'
  [ -n "$_body" ] && set -- "$@" --data-binary "@$_body"
  _code=$(curl "$@" "$_url" 2>/dev/null)
  printf '%s' "${_code:-000}" > "$HTTP_STATUS_FILE"
  cat "$HTTP_BODY" 2>/dev/null
  case "${_code:-000}" in 2*) return 0 ;; *) return 1 ;; esac
}

# ---------- JSON ----------

# One flat object of string values on stdin -> one file per key in <dir>.
#
# Files rather than --from-literal so values never reach the process list and
# may contain any byte. jq coerces numbers and emits multi-line output for
# nested values, so the type check is explicit: a credential silently turned
# into "123" or "{" is worse than a refused payload.
#
# Keys become filenames, so anything outside the env-var charset is skipped
# rather than used to build a path from untrusted input.
json_to_files() {
  _dir="$1"
  _in="$_dir/.payload"
  cat > "$_in"

  if ! jq -e '
        if type != "object" then error("expected a JSON object")
        else (to_entries | map(select(.value | type != "string"))) as $bad
          | if ($bad | length) > 0
            then error("value of \"\($bad[0].key)\" is not a string; store every value quoted")
            else true end
        end' "$_in" >/dev/null 2>"$_dir/.jqerr"; then
    sed -E 's/^jq: error[^:]*: ?/ERROR: /' "$_dir/.jqerr" >&2
    rm -f "$_in" "$_dir/.jqerr"
    return 1
  fi

  _n=0
  jq -r 'keys_unsorted[]' "$_in" > "$_dir/.keys"
  while IFS= read -r _k; do
    case "$_k" in
      [A-Za-z_]*) ;;
      *) warn "skipping key with unusable name: $_k"; continue ;;
    esac
    case "$_k" in
      *[!A-Za-z0-9_.-]*) warn "skipping key with unusable name: $_k"; continue ;;
    esac
    # -j: no trailing newline, so the value stays byte-exact.
    jq -rj --arg k "$_k" '.[$k]' "$_in" > "$_dir/$_k"
    _n=$((_n + 1))
  done < "$_dir/.keys"

  rm -f "$_in" "$_dir/.keys" "$_dir/.jqerr"
  printf '%s' "$_n"
}

# One key's value from a JSON object on stdin. Returns 2 if absent.
# Provider responses embed the payload as an escaped JSON string, which jq
# decodes correctly.
json_one() {
  _f="/tmp/.json_one.$$"
  cat > "$_f"
  if ! jq -e --arg k "$1" 'has($k)' "$_f" >/dev/null 2>&1; then rm -f "$_f"; return 2; fi
  jq -rj --arg k "$1" '.[$k]' "$_f"
  rm -f "$_f"
}

# ---------- Kubernetes ----------

HASH_ANNOTATION="nected.ai/payload-hash"

k8s_secret_exists() { kubectl get secret "$1" >/dev/null 2>&1; }

k8s_secret_hash() {
  kubectl get secret "$1" -o "jsonpath={.metadata.annotations['nected\.ai/payload-hash']}" 2>/dev/null
}

# Reads one key back out of a Secret, base64 as stored.
k8s_secret_value_b64() {
  kubectl get secret "$1" -o "jsonpath={.data['$2']}" 2>/dev/null
}

# Create or replace a Secret from a directory of files, one per key.
#
# Each stage runs separately rather than as one pipeline: a pipeline reports
# only the last command's status, so a failure in create or annotate used to
# surface as an unexplained "could not write Secret".
k8s_apply_secret_from_dir() {
  _name="$1"; _dir="$2"; _hash="$3"
  _m1="$WORK/manifest.1"; _m2="$WORK/manifest.2"; _err="$WORK/kubectl.err"

  if ! kubectl create secret generic "$_name" --from-file="$_dir" \
         --dry-run=client -o yaml > "$_m1" 2>"$_err"; then
    warn "building the Secret manifest failed:"; sed 's/^/    /' "$_err" >&2; return 1
  fi
  if ! kubectl annotate --local -f "$_m1" "${HASH_ANNOTATION}=${_hash}" \
         --dry-run=client -o yaml > "$_m2" 2>"$_err"; then
    warn "annotating the Secret manifest failed:"; sed 's/^/    /' "$_err" >&2; return 1
  fi
  if ! kubectl apply -f "$_m2" >/dev/null 2>"$_err"; then
    warn "applying the Secret failed:"; sed 's/^/    /' "$_err" >&2; return 1
  fi
}

# Values taken from envFrom or secretKeyRef are fixed when a container starts,
# so a rotated Secret stays invisible until pods are replaced.
k8s_restart() {
  for _d in $1; do
    if kubectl patch deployment "$_d" \
         -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"${HASH_ANNOTATION}\":\"$2\"}}}}}" \
         >/dev/null 2>&1; then
      note "  restarted Deployment/$_d"
    else
      # Expected on a first install: the Deployment does not exist yet when the
      # pre-install hook runs, and new pods read the Secret anyway.
      note "  Deployment/$_d not present yet; skipping"
    fi
  done
}
