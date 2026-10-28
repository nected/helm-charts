# Azure Key Vault provider.
#
# Simpler than AWS: Key Vault takes a bearer token, so there is no request
# signing at all. The only awkwardness is that set-secret is a PUT, which
# busybox wget cannot send - that one call goes through openssl s_client.

AZ_TOKEN=""

provider_name() { echo "Azure Key Vault"; }

_kv_host()   { printf '%s' "$AZURE_VAULT_URL" | sed -e 's|^[a-z]*://||' -e 's|/.*$||'; }
_kv_scheme() { _s=$(printf '%s' "$AZURE_VAULT_URL" | sed -n 's|^\([a-z]*\)://.*|\1|p'); printf '%s' "${_s:-https}"; }

# Workload Identity: the webhook projects a federated token which is exchanged
# for an access token. AZURE_AUTHORITY_HOST comes from the webhook too, so
# sovereign clouds work without special-casing.
provider_init() {
  [ -n "${AZURE_VAULT_URL:-}" ] || { warn "no Key Vault URL configured"; return 1; }

  if [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ] && [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]; then
    _assert=$(cat "$AZURE_FEDERATED_TOKEN_FILE" 2>/dev/null) || { warn "could not read the federated token"; return 1; }
    _authority="${AZURE_AUTHORITY_HOST:-https://login.microsoftonline.com/}"
    case "$_authority" in */) ;; *) _authority="${_authority}/" ;; esac

    printf 'client_id=%s&scope=%s&client_assertion_type=%s&client_assertion=%s&grant_type=client_credentials' \
      "$(url_encode "$AZURE_CLIENT_ID")" \
      "$(url_encode 'https://vault.azure.net/.default')" \
      "$(url_encode 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer')" \
      "$(url_encode "$_assert")" > /tmp/.aztok.$$

    _r=$(http_send POST "${_authority}${AZURE_TENANT_ID}/oauth2/v2.0/token" /tmp/.aztok.$$ \
           "Content-Type: application/x-www-form-urlencoded")
    _rc=$?; rm -f /tmp/.aztok.$$
    [ $_rc -eq 0 ] || { warn "token exchange failed (status $(http_status))"; return 1; }

    AZ_TOKEN=$(printf '%s' "$_r" | json_one access_token)
    [ -n "$AZ_TOKEN" ] && { note "  identity: Azure Workload Identity"; return 0; }
    warn "token endpoint returned no access_token"
    return 1
  fi

  # Escape hatch for running outside a cluster.
  if [ -n "${AZURE_ACCESS_TOKEN:-}" ]; then
    AZ_TOKEN="$AZURE_ACCESS_TOKEN"
    note "  identity: supplied access token"
    return 0
  fi

  warn "no Azure identity found: expected Workload Identity env (AZURE_CLIENT_ID,"
  warn "AZURE_TENANT_ID, AZURE_FEDERATED_TOKEN_FILE). Is the pod labelled"
  warn "azure.workload.identity/use=true and the service account annotated?"
  return 1
}

provider_get() {
  _r=$(http_send GET "$(_kv_scheme)://$(_kv_host)/secrets/$1?api-version=7.4" "" \
         "Authorization: Bearer ${AZ_TOKEN}")
  if [ $? -eq 0 ]; then
    printf '%s' "$_r" | json_one value
    return 0
  fi
  [ "$(http_status)" = "404" ] && return 2
  warn "reading '$1' from Key Vault failed (status $(http_status))"
  return 1
}

# Key Vault secrets are strings only, so the value is stored as the same base64
# the Kubernetes Secret already holds. That also matches what
# commonSecret.secretValue expects, which keeps restore a copy-paste.
#
# set-secret is the same PUT whether the item exists or not, so create and
# update are one operation here.
_kv_set() {
  printf '{"value":"%s"}' "$(cat "$2")" > /tmp/.kvput.$$
  https_put "$(_kv_host)" "/secrets/$1?api-version=7.4" /tmp/.kvput.$$ \
    "Authorization: Bearer ${AZ_TOKEN}" "Content-Type: application/json"
  _rc=$?
  rm -f /tmp/.kvput.$$
  [ $_rc -eq 0 ] || warn "writing '$1' to Key Vault failed (status $(http_status))"
  return $_rc
}

provider_create() { _kv_set "$@"; }
provider_update() { _kv_set "$@"; }

provider_exists() {
  http_send GET "$(_kv_scheme)://$(_kv_host)/secrets/$1?api-version=7.4" "" \
    "Authorization: Bearer ${AZ_TOKEN}" >/dev/null 2>&1
}
