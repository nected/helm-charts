{{/*
Render-time guards for values that install cleanly and then fail in the cluster.

Pointing a store at the Secret the sync job would create, while telling the job
not to create one, is only detectable here: this chart sees both halves. Left
alone, helm reports success and the server pods fail with

  Error: secret "nected-credential" not found
*/}}
{{- define "temporal.migrationGuards" -}}

{{- $sm := default dict .Values.secretsmanager }}
{{- $creds := default dict $sm.credentials }}
{{- $target := default "" $creds.secret }}

{{- if and (not $creds.enabled) $target }}
{{- $server := default dict .Values.server }}
{{- $cfg := default dict $server.config }}
{{- $persistence := default dict $cfg.persistence }}
{{- range $store := list "default" "visibility" }}
{{- $sql := default dict (get (default dict (get $persistence $store)) "sql") }}
{{- if eq (default "" $sql.existingSecret) $target }}
{{- fail (printf "server.config.persistence.%s.sql.existingSecret is %q, which is the Secret secretsmanager.credentials would create, but secretsmanager.credentials.enabled is false - so nothing creates it and the temporal pods will fail with `secret %q not found`.\n\nPick one:\n  - set secretsmanager.credentials.enabled: true (and provider + remoteKeys) to have the job write it\n  - clear existingSecret and set an inline password instead\n  - point existingSecret at a Secret you create yourself, under a different name from secretsmanager.credentials.secret"
      $store $target $target) }}
{{- end }}
{{- end }}

{{/* elasticsearch.external forces the visibility store onto this block. */}}
{{- $es := default dict .Values.elasticsearch }}
{{- if eq (default "" $es.existingSecret) $target }}
{{- fail (printf "elasticsearch.existingSecret is %q, which secretsmanager.credentials would create, but secretsmanager.credentials.enabled is false. Either enable credentials or point it at a Secret you create yourself." $target) }}
{{- end }}
{{- end }}

{{- end -}}
