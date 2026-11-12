{{/*
Fail the render when a values file still uses a key that moved.

Helm silently ignores unknown top-level keys, so without these a stale file
would install happily and lose the behaviour it was configuring. For
commonSecret.secretValue that is not a misconfiguration but data loss: a new
encryption-at-rest key would be generated and anything encrypted under the old
one becomes unreadable.
*/}}
{{- define "nected.migrationGuards" -}}

{{- if hasKey .Values "commonSecret" }}
{{- $v := .Values.commonSecret }}
{{- fail (printf "`commonSecret` moved into the secretsmanager subchart.\n\n  secretsmanager:\n    commonSecret:\n      enabled: %v\n      secretValue: %q\n\nIf you relied on secretValue you MUST carry it across: without it a new\nencryption-at-rest key is generated and data encrypted with the old key\nbecomes unreadable. Job settings moved too: commonSecret.image ->\nsecretsmanager.image, .backoffLimit and .resources likewise."
      (default true $v.enabled) (default "" $v.secretValue)) }}
{{- end }}

{{- if hasKey .Values "secretManager" }}
{{- fail "`secretManager` was replaced by the secretsmanager subchart. Use secretsmanager.provider, secretsmanager.credentials and secretsmanager.commonSecret." }}
{{- end }}


{{/*
Pointing the services at the Secret the sync job would create, while telling it
not to create one, is only detectable here: the parent sees both halves. Left
alone it installs cleanly and every pod then fails with

  Error: secret "nected-credential" not found

because secretKeys has also stripped those values out of the ConfigMap, so
there is no fallback. A Secret you create yourself is fine - it just must not
be named after the job's own target.
*/}}
{{- $sm := default dict .Values.secretsmanager }}
{{- $creds := default dict $sm.credentials }}
{{- $target := default "" $creds.secret }}
{{- if and (not $creds.enabled) $target (eq (default "" .Values.existingSecret) $target) }}
{{- fail (printf "existingSecret is %q, which is the Secret secretsmanager.credentials would create, but secretsmanager.credentials.enabled is false - so nothing creates it and every pod will fail with `secret %q not found`.\n\nPick one:\n  - set secretsmanager.credentials.enabled: true (and provider + remoteKeys) to have the job write it\n  - clear existingSecret and secretKeys, so the values come from envVars as before\n  - point existingSecret at a Secret you create yourself, under a different name from secretsmanager.credentials.secret"
      $target $target) }}
{{- end }}

{{/*
secretKeys without a Secret to read them from is the same trap one step removed:
the ConfigMap loses the values and nothing replaces them.
*/}}
{{- if and (not (default "" .Values.existingSecret)) (default (list) .Values.secretKeys) }}
{{- fail (printf "secretKeys lists %d keys to keep out of the ConfigMap, but existingSecret is empty, so nothing supplies them and the services will start with those variables unset. Set existingSecret, or clear secretKeys."
      (len .Values.secretKeys)) }}
{{- end }}

{{- end -}}
