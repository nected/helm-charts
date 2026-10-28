# AWS Secrets Manager provider.
#
# Requests are signed with SigV4 built from the openssl in the job image, which
# is why no AWS CLI (+421MB) or boto3 (+102MB) is needed. The signature has
# been checked byte for byte against aws-sdk-go-v2 for both the plain and the
# session-token case.

SERVICE="secretsmanager"
AKID=""; SKEY=""; STOKEN=""

provider_name() { echo "AWS Secrets Manager"; }

_sm_host() {
  if [ -n "${SM_ENDPOINT:-}" ]; then
    printf '%s' "$SM_ENDPOINT" | sed -e 's|^[a-z]*://||' -e 's|/.*$||'
  else
    printf '%s.%s.amazonaws.com' "$SERVICE" "$AWS_REGION"
  fi
}
_sm_scheme() {
  if [ -n "${SM_ENDPOINT:-}" ]; then
    _s=$(printf '%s' "$SM_ENDPOINT" | sed -n 's|^\([a-z]*\)://.*|\1|p')
    printf '%s' "${_s:-https}"
  else
    printf 'https'
  fi
}

# Credentials come from whichever identity the platform injected; the chart
# never configures static keys.
provider_init() {
  [ -n "${AWS_REGION:-}" ] || { warn "no AWS region configured"; return 1; }

  # EKS Pod Identity / ECS task role: plain HTTP to a link-local endpoint.
  if [ -n "${AWS_CONTAINER_CREDENTIALS_FULL_URI:-}" ] && [ -n "${AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE:-}" ]; then
    _t=$(cat "$AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE" 2>/dev/null) || return 1
    _r=$(http_send GET "$AWS_CONTAINER_CREDENTIALS_FULL_URI" "" "Authorization: $_t") || return 1
    AKID=$(printf '%s' "$_r" | json_one AccessKeyId)
    SKEY=$(printf '%s' "$_r" | json_one SecretAccessKey)
    STOKEN=$(printf '%s' "$_r" | json_one Token)
    [ -n "$AKID" ] && [ -n "$SKEY" ] && { note "  identity: EKS Pod Identity"; return 0; }
    warn "Pod Identity endpoint returned no usable credentials"; return 1
  fi

  # IRSA: trade the projected service account token at STS. Unsigned call.
  if [ -n "${AWS_ROLE_ARN:-}" ] && [ -n "${AWS_WEB_IDENTITY_TOKEN_FILE:-}" ]; then
    _jwt=$(cat "$AWS_WEB_IDENTITY_TOKEN_FILE" 2>/dev/null) || return 1
    printf 'Action=AssumeRoleWithWebIdentity&Version=2011-06-15&RoleSessionName=secretsmanager&RoleArn=%s&WebIdentityToken=%s' \
      "$(url_encode "$AWS_ROLE_ARN")" "$(url_encode "$_jwt")" > /tmp/.sts.$$
    _r=$(http_send POST "https://sts.${AWS_REGION}.amazonaws.com/" /tmp/.sts.$$ \
           "Content-Type: application/x-www-form-urlencoded")
    _rc=$?; rm -f /tmp/.sts.$$
    [ $_rc -eq 0 ] || { warn "STS AssumeRoleWithWebIdentity failed (status $(http_status))"; return 1; }
    AKID=$(printf '%s' "$_r" | xml_field AccessKeyId)
    SKEY=$(printf '%s' "$_r" | xml_field SecretAccessKey)
    STOKEN=$(printf '%s' "$_r" | xml_field SessionToken)
    [ -n "$AKID" ] && [ -n "$SKEY" ] && { note "  identity: IRSA"; return 0; }
    warn "STS returned no usable credentials"; return 1
  fi

  # Static keys, for running this outside a cluster.
  if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    AKID="$AWS_ACCESS_KEY_ID"; SKEY="$AWS_SECRET_ACCESS_KEY"; STOKEN="${AWS_SESSION_TOKEN:-}"
    note "  identity: static credentials"
    return 0
  fi

  # Report exactly what was and was not injected: the usual causes are a
  # missing PodIdentityAssociation, an association naming a different service
  # account or namespace, or the EKS Pod Identity Agent addon not running.
  warn "no AWS identity found. What this pod can see:"
  warn "  Pod Identity:"
  warn "    AWS_CONTAINER_CREDENTIALS_FULL_URI      = ${AWS_CONTAINER_CREDENTIALS_FULL_URI:-<unset>}"
  warn "    AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE  = ${AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE:-<unset>}"
  warn "  IRSA:"
  warn "    AWS_ROLE_ARN                            = ${AWS_ROLE_ARN:-<unset>}"
  warn "    AWS_WEB_IDENTITY_TOKEN_FILE             = ${AWS_WEB_IDENTITY_TOKEN_FILE:-<unset>}"
  warn "  serviceaccount token dirs present:"
  for _d in /var/run/secrets/pods.eks.amazonaws.com/serviceaccount \
            /var/run/secrets/eks.amazonaws.com/serviceaccount \
            /var/run/secrets/kubernetes.io/serviceaccount; do
    [ -d "$_d" ] && warn "    $_d" || warn "    $_d  (absent)"
  done
  warn ""
  warn "Both env pairs unset means nothing was injected. Check, in order:"
  warn "  1. the association exists and names THIS namespace and service account:"
  warn "       aws eks list-pod-identity-associations --cluster-name <cluster>"
  warn "     it must match namespace=${NAMESPACE:-<unset>} serviceAccount=${SA_NAME:-<unset>}"
  warn "  2. the agent addon is running:"
  warn "       kubectl get ds -n kube-system eks-pod-identity-agent"
  warn "  3. for IRSA instead, annotate the service account with"
  warn "       eks.amazonaws.com/role-arn"
  return 1
}

# aws_call <Target> <json body> - signed POST; body on stdout.
aws_call() {
  _target="$1"; _body="$2"
  _host=$(_sm_host); _scheme=$(_sm_scheme)
  _amzdate="${SIGV4_FIXED_DATE:-$(date -u +%Y%m%dT%H%M%SZ)}"
  _datestamp=$(printf '%s' "$_amzdate" | cut -c1-8)
  _ctype="application/x-amz-json-1.1"
  _amztarget="secretsmanager.${_target}"
  _phash=$(printf '%s' "$_body" | sha256_hex)

  # Signed headers must be lowercase, sorted, and match the set exactly.
  if [ -n "$STOKEN" ]; then
    _ch="content-type:${_ctype}
host:${_host}
x-amz-date:${_amzdate}
x-amz-security-token:${STOKEN}
x-amz-target:${_amztarget}
"
    _sh="content-type;host;x-amz-date;x-amz-security-token;x-amz-target"
  else
    _ch="content-type:${_ctype}
host:${_host}
x-amz-date:${_amzdate}
x-amz-target:${_amztarget}
"
    _sh="content-type;host;x-amz-date;x-amz-target"
  fi

  _creq="POST
/

${_ch}
${_sh}
${_phash}"

  _scope="${_datestamp}/${AWS_REGION}/${SERVICE}/aws4_request"
  _sts="AWS4-HMAC-SHA256
${_amzdate}
${_scope}
$(printf '%s' "$_creq" | sha256_hex)"

  # Seeding the HMAC chain via hex avoids quoting trouble with / and + in the
  # secret access key.
  _k=$(printf '%s' "AWS4${SKEY}" | to_hex)
  _k=$(printf '%s' "$_datestamp"  | hmac_hex "$_k")
  _k=$(printf '%s' "$AWS_REGION"  | hmac_hex "$_k")
  _k=$(printf '%s' "$SERVICE"     | hmac_hex "$_k")
  _k=$(printf '%s' "aws4_request" | hmac_hex "$_k")
  _sig=$(printf '%s' "$_sts" | hmac_hex "$_k")

  _auth="AWS4-HMAC-SHA256 Credential=${AKID}/${_scope}, SignedHeaders=${_sh}, Signature=${_sig}"
  if [ -n "${SIGV4_PRINT_AUTH:-}" ]; then printf '%s\n' "$_auth"; return 0; fi

  printf '%s' "$_body" > /tmp/.smbody.$$
  if [ -n "$STOKEN" ]; then
    http_send POST "${_scheme}://${_host}/" /tmp/.smbody.$$ \
      "Content-Type: ${_ctype}" "X-Amz-Date: ${_amzdate}" "X-Amz-Target: ${_amztarget}" \
      "X-Amz-Security-Token: ${STOKEN}" "Authorization: ${_auth}"
  else
    http_send POST "${_scheme}://${_host}/" /tmp/.smbody.$$ \
      "Content-Type: ${_ctype}" "X-Amz-Date: ${_amzdate}" "X-Amz-Target: ${_amztarget}" \
      "Authorization: ${_auth}"
  fi
  _rc=$?
  rm -f /tmp/.smbody.$$
  return $_rc
}

# Pulls the error out of an x-amz-json-1.1 fault body and explains it.
HINTED_FILE="/tmp/.aws_hinted.$$"

_aws_explain() {
  _op="$1"; _id="$2"; _body="$3"
  _type=$(printf '%s' "$_body" | sed -n 's/.*"__type"[^"]*"\([^"]*\)".*/\1/p' | head -1)
  _msg=$(printf '%s' "$_body" | sed -n 's/.*"[Mm]essage"[^"]*"\([^"]*\)".*/\1/p' | head -1)
  warn "$_op '$_id' failed: HTTP $(http_status) ${_type:-unknown error}"
  [ -n "$_msg" ] && warn "  $_msg"
  # The remediation is identical for every call, so print it once per run.
  [ -f "$HINTED_FILE" ] && return 0
  : > "$HINTED_FILE"
  case "${_type}" in
    *AccessDeniedException*|*UnrecognizedClientException*|*InvalidSignatureException*)
      warn "  the identity resolved but is not allowed this call. Required:"
      warn "    secretsmanager:GetSecretValue, secretsmanager:DescribeSecret"
      warn "    secretsmanager:CreateSecret   (only for the encryption-at-rest backup)"
      warn "    secretsmanager:PutSecretValue (only with earKey.overwrite=true)"
      warn "    kms:Decrypt, kms:GenerateDataKey (only for a customer-managed key)"
      warn "  and the resource must cover '$_id', e.g."
      warn "    arn:aws:secretsmanager:${AWS_REGION}:<account>:secret:$(printf '%s' "$_id" | cut -d/ -f1)/*"
      ;;
    *ResourceNotFoundException*)
      warn "  no such secret in region ${AWS_REGION}. Check the name and the region."
      ;;
    *ValidationException*|*InvalidParameterException*)
      warn "  the name is not valid for Secrets Manager."
      ;;
    *ResourceExistsException*)
      warn "  the item already exists; nothing was overwritten."
      ;;
  esac
}

# provider_get <remote name> - value on stdout, diagnostics on stderr.
# 0 found, 2 absent, 1 error.
provider_get() {
  _r=$(aws_call GetSecretValue "{\"SecretId\":\"$1\"}")
  if [ $? -eq 0 ]; then
    printf '%s' "$_r" | json_one SecretString
    return 0
  fi
  case "$_r" in
    *ResourceNotFoundException*) return 2 ;;
  esac
  _aws_explain GetSecretValue "$1" "$_r"
  return 1
}

# provider_create / provider_update <remote name> <file holding a base64 value>
# Callers already know whether the item exists, so neither re-checks.
provider_create() {
  _r=$(aws_call CreateSecret "{\"Name\":\"$1\",\"ClientRequestToken\":\"$(new_uuid)\",\"SecretString\":\"$(cat "$2")\"}")
  [ $? -eq 0 ] && return 0
  _aws_explain CreateSecret "$1" "$_r"
  return 1
}

provider_update() {
  _r=$(aws_call PutSecretValue "{\"SecretId\":\"$1\",\"ClientRequestToken\":\"$(new_uuid)\",\"SecretString\":\"$(cat "$2")\"}")
  [ $? -eq 0 ] && return 0
  _aws_explain PutSecretValue "$1" "$_r"
  return 1
}

# Quiet by design: a miss here is the normal "not backed up yet" case and the
# caller decides what it means.
provider_exists() { aws_call DescribeSecret "{\"SecretId\":\"$1\"}" >/dev/null 2>&1; }
