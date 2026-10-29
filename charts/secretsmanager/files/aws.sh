# AWS Secrets Manager provider.
#
# Requests are signed by curl's --aws-sigv4, so there is no signing code here
# and no need for the AWS CLI (~421MB) or boto3 (~102MB). The signature was
# verified against a server-side recomputation, with and without a session
# token.

SERVICE="secretsmanager"
AKID=""; SKEY=""; STOKEN=""

provider_name() { echo "AWS Secrets Manager"; }

_sm_url() {
  if [ -n "${SM_ENDPOINT:-}" ]; then
    printf '%s' "${SM_ENDPOINT%/}/"
  else
    printf 'https://%s.%s.amazonaws.com/' "$SERVICE" "$AWS_REGION"
  fi
}

# Credentials come from whichever identity the platform injected; the chart
# never configures static keys.
provider_init() {
  [ -n "${AWS_REGION:-}" ] || { warn "no AWS region configured"; return 1; }

  # EKS Pod Identity / ECS task role: plain HTTP to a link-local endpoint.
  if [ -n "${AWS_CONTAINER_CREDENTIALS_FULL_URI:-}" ] && [ -n "${AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE:-}" ]; then
    _t=$(cat "$AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE" 2>/dev/null) || return 1
    _r=$(http_send GET "$AWS_CONTAINER_CREDENTIALS_FULL_URI" "" -H "Authorization: $_t") || return 1
    AKID=$(printf '%s' "$_r" | json_one AccessKeyId)
    SKEY=$(printf '%s' "$_r" | json_one SecretAccessKey)
    STOKEN=$(printf '%s' "$_r" | json_one Token)
    [ -n "$AKID" ] && [ -n "$SKEY" ] && { note "  identity: EKS Pod Identity"; return 0; }
    warn "the Pod Identity endpoint returned no usable credentials"; return 1
  fi

  # IRSA: trade the projected service account token at STS. Unsigned call.
  if [ -n "${AWS_ROLE_ARN:-}" ] && [ -n "${AWS_WEB_IDENTITY_TOKEN_FILE:-}" ]; then
    _r=$(curl -sS -m 30 \
           --data-urlencode "Action=AssumeRoleWithWebIdentity" \
           --data-urlencode "Version=2011-06-15" \
           --data-urlencode "RoleSessionName=nected-secretsmanager" \
           --data-urlencode "RoleArn=${AWS_ROLE_ARN}" \
           --data-urlencode "WebIdentityToken@${AWS_WEB_IDENTITY_TOKEN_FILE}" \
           "https://sts.${AWS_REGION}.amazonaws.com/" 2>/dev/null) || {
      warn "STS AssumeRoleWithWebIdentity failed"; return 1; }
    AKID=$(printf '%s' "$_r" | sed -n 's|.*<AccessKeyId>\([^<]*\)</AccessKeyId>.*|\1|p' | head -1)
    SKEY=$(printf '%s' "$_r" | sed -n 's|.*<SecretAccessKey>\([^<]*\)</SecretAccessKey>.*|\1|p' | head -1)
    STOKEN=$(printf '%s' "$_r" | sed -n 's|.*<SessionToken>\([^<]*\)</SessionToken>.*|\1|p' | head -1)
    [ -n "$AKID" ] && [ -n "$SKEY" ] && { note "  identity: IRSA"; return 0; }
    warn "STS returned no usable credentials"; return 1
  fi

  # Static keys, for running this outside a cluster.
  if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    AKID="$AWS_ACCESS_KEY_ID"; SKEY="$AWS_SECRET_ACCESS_KEY"; STOKEN="${AWS_SESSION_TOKEN:-}"
    note "  identity: static credentials"
    return 0
  fi

  # Both env pairs unset means nothing was injected. The usual causes are a
  # missing PodIdentityAssociation, one naming a different namespace or service
  # account, or the Pod Identity Agent addon not running.
  warn "no AWS identity found. What this pod can see:"
  warn "    AWS_CONTAINER_CREDENTIALS_FULL_URI     = ${AWS_CONTAINER_CREDENTIALS_FULL_URI:-<unset>}"
  warn "    AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE = ${AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE:-<unset>}"
  warn "    AWS_ROLE_ARN                           = ${AWS_ROLE_ARN:-<unset>}"
  warn "    AWS_WEB_IDENTITY_TOKEN_FILE            = ${AWS_WEB_IDENTITY_TOKEN_FILE:-<unset>}"
  warn "  Check, in order:"
  warn "    1. aws eks list-pod-identity-associations --cluster-name <cluster>"
  warn "       must list namespace=${NAMESPACE:-<unset>} serviceAccount=${SA_NAME:-<unset>}"
  warn "    2. kubectl get ds -n kube-system eks-pod-identity-agent"
  warn "    3. for IRSA instead, set serviceAccount.roleArn"
  return 1
}

# aws_call <Target> <json body> - signed POST, body on stdout.
aws_call() {
  _target="$1"
  printf '%s' "$2" > "$WORK/sm.body"
  set -- --aws-sigv4 "aws:amz:${AWS_REGION}:${SERVICE}" \
         -u "${AKID}:${SKEY}" \
         -H "Content-Type: application/x-amz-json-1.1" \
         -H "X-Amz-Target: ${SERVICE}.${_target}"
  [ -n "$STOKEN" ] && set -- "$@" -H "X-Amz-Security-Token: ${STOKEN}"
  http_send POST "$(_sm_url)" "$WORK/sm.body" "$@"
}

# Explains an x-amz-json-1.1 fault. The actionable detail is printed once per
# run; repeating it per call buries the useful line.
_HINTED="$WORK/.aws_hinted"
_aws_explain() {
  _op="$1"; _id="$2"; _body="$3"
  _type=$(printf '%s' "$_body" | jq -r '.__type // empty' 2>/dev/null)
  _msg=$(printf '%s' "$_body" | jq -r '.message // .Message // empty' 2>/dev/null)
  warn "$_op '$_id' failed: HTTP $(http_status) ${_type:-unknown error}"
  [ -n "$_msg" ] && warn "  $_msg"
  [ -f "$_HINTED" ] && return 0
  : > "$_HINTED"
  case "$_type" in
    *AccessDenied*|*UnrecognizedClient*|*InvalidSignature*)
      warn "  the identity resolved but is not allowed this call. Required:"
      warn "    secretsmanager:GetSecretValue, secretsmanager:DescribeSecret"
      warn "    secretsmanager:CreateSecret   (encryption-at-rest backup only)"
      warn "    secretsmanager:PutSecretValue (only with commonSecret.overwrite)"
      warn "    kms:Decrypt, kms:GenerateDataKey (customer-managed key only)"
      warn "  Secret ARNs carry a random suffix, so scope the policy with a"
      warn "  wildcard: arn:aws:secretsmanager:${AWS_REGION}:<account>:secret:$(printf '%s' "$_id" | cut -d/ -f1)/*"
      ;;
    *ResourceNotFound*) warn "  no such secret in ${AWS_REGION}. Check the name and the region." ;;
    *ResourceExists*)   warn "  the item already exists; nothing was overwritten." ;;
    *Validation*|*InvalidParameter*) warn "  the name is not valid for Secrets Manager." ;;
  esac
}

# provider_get <name> - value on stdout. 0 found, 2 absent, 1 error.
provider_get() {
  _r=$(aws_call GetSecretValue "{\"SecretId\":\"$1\"}")
  if [ $? -eq 0 ]; then printf '%s' "$_r" | json_one SecretString; return 0; fi
  case "$_r" in *ResourceNotFoundException*) return 2 ;; esac
  _aws_explain GetSecretValue "$1" "$_r"
  return 1
}

provider_exists() { aws_call DescribeSecret "{\"SecretId\":\"$1\"}" >/dev/null 2>&1; }

provider_create() {
  _r=$(aws_call CreateSecret \
        "{\"Name\":\"$1\",\"ClientRequestToken\":\"$(new_uuid)\",\"SecretString\":\"$(cat "$2")\"}")
  [ $? -eq 0 ] && return 0
  _aws_explain CreateSecret "$1" "$_r"
  return 1
}

provider_update() {
  _r=$(aws_call PutSecretValue \
        "{\"SecretId\":\"$1\",\"ClientRequestToken\":\"$(new_uuid)\",\"SecretString\":\"$(cat "$2")\"}")
  [ $? -eq 0 ] && return 0
  _aws_explain PutSecretValue "$1" "$_r"
  return 1
}
