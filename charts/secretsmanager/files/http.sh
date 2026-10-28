# HTTP helpers. Sourced by the provider files.
#
# busybox wget only speaks GET and POST, so the one call that needs PUT
# (Azure Key Vault set-secret) goes through openssl s_client instead. Keeping
# body parsing on wget means chunked transfer-encoding stays wget's problem.

HTTP_BODY="/tmp/.http_body.$$"
HTTP_HDR="/tmp/.http_hdr.$$"
HTTP_STATUS_FILE="/tmp/.http_status.$$"

http_cleanup() { rm -f "$HTTP_BODY" "$HTTP_HDR" "$HTTP_STATUS_FILE"; }

# Callers run http_send inside command substitution, so the status has to
# cross a subshell boundary.
http_status() { cat "$HTTP_STATUS_FILE" 2>/dev/null || echo "?"; }
_set_status() { printf '%s' "${1:-?}" > "$HTTP_STATUS_FILE"; }

_http_status_from_hdr() {
  sed -n 's|^ *HTTP/[0-9.]* \([0-9][0-9][0-9]\).*|\1|p' "$HTTP_HDR" | tail -1
}

# Certificate verification is NOT on by default in s_client: without these
# flags it happily completes a handshake with a self-signed certificate, which
# would hand the bearer token to a man in the middle. wget verifies via
# ssl_client already, so this only applies to the raw path.
CA_BUNDLE="${CA_BUNDLE:-/etc/ssl/certs/ca-certificates.crt}"

# Prefer curl when the image has it.
HTTP_CURL=$(command -v curl 2>/dev/null || true)

# http_send METHOD <url> <body-file-or-empty> [header ...]
# Body on stdout, status readable with http_status. Returns 0 only for a 2xx.
#
# curl is strongly preferred: busybox wget DISCARDS the response body on a 4xx,
# which makes every provider error indistinguishable - no AccessDenied vs
# ResourceNotFound, no message. curl keeps it, and reports the real status.
http_send() {
  _method="$1"; _url="$2"; _bodyfile="$3"; shift 3

  if [ -n "$HTTP_CURL" ]; then
    # Header values contain spaces, so each must stay one argv token. Rotate
    # them from the front of "$@" to the back as ("-H", "Name: value") pairs.
    _cnt=$#; _i=0
    while [ "$_i" -lt "$_cnt" ]; do
      _h="$1"; shift
      set -- "$@" -H "$_h"
      _i=$((_i + 1))
    done
    if [ -n "$_bodyfile" ]; then
      set -- "$@" --data-binary "@$_bodyfile"
    fi
    _code=$(curl -sS -m 30 -X "$_method" -o "$HTTP_BODY" -w '%{http_code}' \
              "$@" "$_url" 2>"$HTTP_HDR")
    _set_status "$_code"
    cat "$HTTP_BODY" 2>/dev/null
    case "${_code:-0}" in 2*) return 0 ;; *) return 1 ;; esac
  fi

  # wget fallback for the older image. Error bodies are lost here, so provider
  # diagnostics will be thin.
  _cnt=$#; _i=0
  while [ "$_i" -lt "$_cnt" ]; do
    _h="$1"; shift
    set -- "$@" --header "$_h"
    _i=$((_i + 1))
  done
  : > "$HTTP_HDR"
  if [ "$_method" = "POST" ]; then
    wget -S -q -T 30 -O "$HTTP_BODY" "$@" --post-file "$_bodyfile" "$_url" 2> "$HTTP_HDR"
  else
    wget -S -q -T 30 -O "$HTTP_BODY" "$@" "$_url" 2> "$HTTP_HDR"
  fi
  _rc=$?
  _set_status "$(_http_status_from_hdr)"
  cat "$HTTP_BODY" 2>/dev/null
  return $_rc
}

# https_put <host> <path-with-query> <body-file> <header> [header ...]
https_put() {
  _host="$1"; _path="$2"; _bodyfile="$3"; shift 3

  if [ -n "$HTTP_CURL" ]; then
    http_send PUT "https://${_host}${_path}" "$_bodyfile" "$@"
    return $?
  fi

  # No curl: busybox wget cannot send PUT, so craft the request directly.
  # s_client does NOT verify certificates without these flags - it will
  # complete a handshake with a self-signed certificate and hand over the
  # bearer token.
  _len=$(wc -c < "$_bodyfile" | tr -d ' ')
  {
    printf 'PUT %s HTTP/1.1\r\n' "$_path"
    printf 'Host: %s\r\n' "$_host"
    for _h in "$@"; do printf '%s\r\n' "$_h"; done
    printf 'Content-Length: %s\r\n' "$_len"
    printf 'Connection: close\r\n\r\n'
    cat "$_bodyfile"
  } | openssl s_client -quiet \
        -verify_return_error -verify 5 -CAfile "$CA_BUNDLE" \
        -connect "$_host:443" -servername "$_host" 2>/dev/null > "$HTTP_HDR"
  _set_status "$(sed -n '1s|^HTTP/[0-9.]* \([0-9][0-9][0-9]\).*|\1|p' "$HTTP_HDR")"
  case "$(http_status)" in
    2*) return 0 ;;
    *)  return 1 ;;
  esac
}
