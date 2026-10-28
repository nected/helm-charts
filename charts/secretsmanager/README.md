# secretsmanager

Materialises Nected's Kubernetes Secrets from **AWS Secrets Manager** or
**Azure Key Vault**, and keeps a copy of the encryption-at-rest key in the
vault so it survives loss of the cluster.

Runs once per `helm install`/`helm upgrade`. There is no periodic resync: with
the vault values stable, nothing changes between releases.

No operator, no CRDs, no cluster-scoped RBAC, and no new container image.

## Why this chart exists

The app charts already accept a Secret through `existingSecret`. The only thing
missing was something to put the values in it. Doing that inside the nected
chart meant the same logic in two charts (nected and temporal), a near-duplicate
template that could not share helpers, and an invisible "whichever release runs
first wins" contract between them. One chart, installed first, replaces all of
that with an explicit step.

A customer who does not install this chart is unaffected: the nected chart's own
encryption-at-rest job guards on the Secret already existing, so it simply
no-ops once this chart has run.

## Two ways to run it

### As a subchart (no separate install)

Both the `nected` and `temporal` charts declare this chart as an optional
dependency, disabled by default. Enable it in their values and the sync runs as
part of that release:

```yaml
# nected-values.yaml or temporal-values.yaml
secretsmanager:
  enabled: true
  provider: aws
  aws: { region: ap-south-1 }
  credentials:
    secret: nected-credential          # must match existingSecret
    remoteKeys: [nected/prod/app, nected/prod/immutable]
```

```bash
helm upgrade -i temporal nected/temporal -f temporal-values.yaml
helm upgrade -i nected   nected/nected   -f nected-values.yaml
```

Its hooks sit at weight -10 (ServiceAccount, RBAC, scripts) and -5 (the Job),
ahead of the nected chart's encryption-at-rest job (-1) and nalanda's setup job
(0) — so the Secret exists before anything reads it. Temporal has no other
hooks, so it precedes the schema jobs there.

Enable it in **both** charts and install order stops mattering: whichever
release runs first creates the Secret, and the second sees an unchanged payload
hash and exits without writing or restarting anything.

### As its own release

```bash
helm upgrade -i secretsmanager nected/secretsmanager -f secrets-values.yaml   # first
helm upgrade -i temporal       nected/temporal       -f temporal-values.yaml
helm upgrade -i nected         nected/nected         -f nected-values.yaml
```

Useful when the secrets are owned by a different team or pipeline than the
application releases.

As a standalone release it must be installed first, because temporal's schema
jobs need the database password at install time. It is a
`pre-install,pre-upgrade` hook either way, because a plain Job would not re-run
on upgrade (Job specs are immutable).

Picking up a vault change without a helm run would need a CronJob. That was
removed: it is only useful once something rotates the vault values, and it
would roll the Nected and Temporal pods unattended when they changed.

## What the job does

1. **Encryption-at-rest key** — restores it from the vault if present,
   otherwise generates it, then backs it up.
2. **Application credentials** — reads one or more vault items, merges them,
   validates, and writes the target Secret.
3. **Rolls consumers** — stamps the pod template with the payload hash.

Step 3 is not optional. Values taken from `envFrom` or `secretKeyRef` are fixed
when a container starts; there is no way to change a running process's
environment. A rotated Secret stays invisible until pods are replaced.

An unchanged payload writes nothing and restarts nothing, so a no-op
`helm upgrade` stays a no-op.

## Vault layout

Each credentials item is a **flat JSON object of string values**:

```json
{
  "MASTER_DB_PASSWORD": "...",
  "DB_PASSWORD": "...",
  "ELASTIC_PASSWORD": "...",
  "JWT_SECRET": "..."
}
```

`credentials.remoteKeys` takes several items, merged in order with later
entries winning. That lets values with different rotation rules live apart:

```yaml
credentials:
  remoteKeys:
    - nected/prod/app        # rotatable; a terraform write-only seed rewrites it whole
    - nected/prod/immutable  # AES_SECRET; seeded once, never rewritten
```

`requiredKeys` is checked against the **merged** result, so a key may come from
either item. Validation happens before anything is written, so a malformed
payload never half-applies.

**Azure naming:** Key Vault secret names allow `[a-zA-Z0-9-]` only, so
`nected/prod/app` is invalid there — use `nected-prod-app`. The env var names
live inside the JSON either way. The chart validates this at render time rather
than letting it fail as an opaque 400.

## Identity

No credentials are configured in values. The job uses whichever identity the
platform injected.

| Platform | What you create | values |
|---|---|---|
| EKS Pod Identity | IAM role + `PodIdentityAssociation` on (namespace, `nected-secret-sync`) | **nothing** — the role is attached server-side, not by annotation |
| EKS IRSA (OIDC) | IAM role trusting the cluster OIDC provider, `sub = system:serviceaccount:<ns>:nected-secret-sync` | `serviceAccount.roleArn` |
| AKS Workload Identity | Managed identity + federated credential on `system:serviceaccount:<ns>:nected-secret-sync` | `serviceAccount.clientId` (required) |

`roleArn` and `clientId` render the right annotation for you. Setting both
fails the render, and Azure without `clientId` fails the render rather than
producing a job that cannot authenticate.

The chart adds the `azure.workload.identity/use: "true"` **pod** label itself —
the webhook injects nothing without it, and it is the usual cause of a failure
here.

Permissions needed:

- **AWS:** `secretsmanager:GetSecretValue`, `DescribeSecret`, and — only if
  `earKey.backup` is on — `CreateSecret` (plus `PutSecretValue` with
  `earKey.overwrite`). Add `kms:Decrypt`/`GenerateDataKey` for a CMK.
- **Azure:** `Key Vault Secrets User` to read. Backing the key up needs write,
  so **Key Vault Secrets Officer** — *Secrets User is read-only*.

## Consuming the Secret

```yaml
# nected-values.yaml
existingSecret: nected-credential
```

```yaml
# temporal-values.yaml
server:
  config:
    persistence:
      default:    { sql: { existingSecret: nected-credential, secretKey: MASTER_DB_PASSWORD } }
      visibility: { sql: { existingSecret: nected-credential, secretKey: MASTER_DB_PASSWORD } }
```

With external OpenSearch, `elasticsearch.external: true` **forces** the
visibility store onto the elasticsearch driver, so the password comes from the
`elasticsearch` block instead:

```yaml
elasticsearch:
  external: true
  existingSecret: nected-credential
  secretKey: ELASTIC_PASSWORD
```

Then **delete those keys from the `envVars` blocks.** `envVars` renders into a
ConfigMap, so leaving them there keeps the plaintext readable via
`kubectl get configmap -o yaml` even though the Secret wins at runtime. Setting
`existingSecret` does not remove it.

## Failure behaviour

`failOpen: true` (default) continues when the provider is unreachable **and**
the target Secret already exists, so a transient outage cannot block an
upgrade. A first install has nothing to fall back on and always fails closed.
`failOpen: false` always fails.

The encryption-at-rest backup is always best effort: the key is already in the
cluster by then, so a permission problem warns and the release continues.

`earKey.overwrite` defaults to `false`. If the vault already holds a value the
job leaves it alone — were two clusters pointed at one `remoteKey`, overwriting
would discard the only off-cluster copy of a key that may still decrypt live
data.

## Diagnosing a failure

The job logs the reason. Two cases are worth knowing:

**`no AWS identity found`** - nothing was injected into the pod. The log lists
which env vars and token directories were present, which separates "no
PodIdentityAssociation" from "agent not running".

**`GetSecretValue ... failed: HTTP 400 AccessDeniedException`** - the identity
resolved but the role lacks the call. The log prints the required actions and
the ARN pattern the policy must cover.

A secret ARN carries a random 6-character suffix
(`...:secret:nected/prod/app-AbCdEf`), so a policy scoped to the exact name
without a wildcard never matches. Use `nected/prod/*`.

**Note:** the published `openssl-kubectl:latest` image has no `curl`, and
busybox wget discards HTTP error bodies - so on that image a permissions
failure and a missing secret both report the same generic message. Rebuild the
image from `devops/openssl-docker` (which installs curl and jq) to get the real
error.

## Implementation notes

The job runs in the shared `openssl-kubectl` utility image (~70 MB with curl
and jq). AWS requests are SigV4-signed with `openssl`, or by `curl --aws-sigv4`
where curl is present; Azure uses a bearer token. Adding the AWS CLI would have
cost +421 MB and boto3 +102 MB.

`http.sh` prefers curl when the image has it, falling back to busybox wget.
That matters for diagnostics: wget discards HTTP error bodies, so on a
curl-less image an AWS `AccessDeniedException` and a missing secret report the
same generic failure.

There is no `jq` or `python3` in that image, so `files/json.awk` is a small
hand-written reader for flat JSON objects. It is the riskiest part of the chart
— a parser that silently corrupts a credential is worse than one that refuses
it — so unsupported input is always a hard error, and it has its own test
suite:

```bash
docker run --rm -v "$PWD:/c" -w /c --entrypoint sh \
  public.ecr.aws/f6k1n6r3/openssl-kubectl:latest -c 'sh tests/json_test.sh'
```

Values are passed to `kubectl` as files, never as arguments, so they never
appear in the process list and may contain any byte.
