# Azure Key Vault provider.
#
# Simpler than AWS: Key Vault takes a bearer token, so there is no request
# signing at all.

AZ_TOKEN=""

provider_name() { echo "Azure Key Vault"; }

_kv_base() { printf '%s' "${AZURE_VAULT_URL%/}"; }
_kv_url()  { printf '%s/secrets/%s?api-version=7.4' "$(_kv_base)" "$1"; }

# Workload Identity: the webhook projects a federated token which is exchanged
# for an access token. AZURE_AUTHORITY_HOST comes from the webhook too, so
# sovereign clouds work without special-casing.
provider_init() {
  [ -n "${AZURE_VAULT_URL:-}" ] || { warn "no Key Vault URL configured"; return 1; }

  if [ -n "${AZURE_CLIENT_ID:-}" ] && [ -n "${AZURE_TENANT_ID:-}" ] && [ -n "${AZURE_FEDERATED_TOKEN_FILE:-}" ]; then
    _authority="${AZURE_AUTHORITY_HOST:-https://login.microsoftonline.com/}"
    case "$_authority" in */) ;; *) _authority="${_authority}/" ;; esac

    _r=$(curl -sS -m 30 \
           --data-urlencode "client_id=${AZURE_CLIENT_ID}" \
           --data-urlencode "scope=https://vault.azure.net/.default" \
           --data-urlencode "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
           --data-urlencode "client_assertion@${AZURE_FEDERATED_TOKEN_FILE}" \
           --data-urlencode "grant_type=client_credentials" \
           "${_authority}${AZURE_TENANT_ID}/oauth2/v2.0/token" 2>/dev/null) || {
      warn "the token exchange failed"; return 1; }

    AZ_TOKEN=$(printf '%s' "$_r" | json_one access_token)
    [ -n "$AZ_TOKEN" ] && { note "  identity: Azure Workload Identity"; return 0; }
    warn "the token endpoint returned no access_token"
    warn "  response: $(printf '%s' "$_r" | head -c 200)"
    return 1
  fi

  # Escape hatch for running outside a cluster.
  if [ -n "${AZURE_ACCESS_TOKEN:-}" ]; then
    AZ_TOKEN="$AZURE_ACCESS_TOKEN"
    note "  identity: supplied access token"
    return 0
  fi

  warn "no Azure identity found. Workload Identity needs AZURE_CLIENT_ID,"
  warn "AZURE_TENANT_ID and AZURE_FEDERATED_TOKEN_FILE, which the webhook only"
  warn "injects when the service account is annotated with"
  warn "azure.workload.identity/client-id AND the pod carries the label"
  warn "azure.workload.identity/use=true (this chart adds the label)."
  return 1
}

provider_get() {
  _r=$(http_send GET "$(_kv_url "$1")" "" -H "Authorization: Bearer ${AZ_TOKEN}")
  if [ $? -eq 0 ]; then printf '%s' "$_r" | json_one value; return 0; fi
  [ "$(http_status)" = "404" ] && return 2
  warn "reading '$1' from Key Vault failed: HTTP $(http_status)"
  warn "  $(printf '%s' "$_r" | jq -r '.error.message // empty' 2>/dev/null | head -c 200)"
  return 1
}

provider_exists() {
  http_send GET "$(_kv_url "$1")" "" -H "Authorization: Bearer ${AZ_TOKEN}" >/dev/null 2>&1
}

# Key Vault secrets are strings only, so the value is stored as the same base64
# the Kubernetes Secret already holds. That also matches what
# commonSecret.secretValue expects, keeping a restore a copy-paste.
#
# set-secret is the same PUT whether the item exists or not, so create and
# update are one operation.
_kv_set() {
  jq -n --rawfile v "$2" '{value: $v}' > "$WORK/kv.body"
  if http_send PUT "$(_kv_url "$1")" "$WORK/kv.body" \
       -H "Authorization: Bearer ${AZ_TOKEN}" -H "Content-Type: application/json" >/dev/null; then
    return 0
  fi
  warn "writing '$1' to Key Vault failed: HTTP $(http_status)"
  warn "  Secrets User is read-only; a write needs the Key Vault Secrets Officer role."
  return 1
}

provider_create() { _kv_set "$@"; }
provider_update() { _kv_set "$@"; }
