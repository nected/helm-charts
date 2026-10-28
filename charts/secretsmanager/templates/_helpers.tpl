{{- define "secretsmanager.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "secretsmanager.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "secretsmanager.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "secretsmanager.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Fail the render rather than producing a job that cannot work. */}}
{{- define "secretsmanager.validate" -}}
{{/* The sample values file ships <<placeholder>> markers. Left unreplaced they
     pass through as literal strings and surface much later as a confusing
     runtime error, so catch them here. */}}
{{- range $field, $value := dict
      "aws.region"                 .Values.aws.region
      "azure.vaultUrl"             .Values.azure.vaultUrl
      "credentials.secret"         .Values.credentials.secret
      "earKey.remoteKey"           .Values.earKey.remoteKey
      "serviceAccount.name"        .Values.serviceAccount.name }}
{{- if and $value (regexMatch "<<.*>>" $value) }}
{{- fail (printf "%s is still a placeholder (%q) - fill it in before installing" $field $value) }}
{{- end }}
{{- end }}
{{- range $k := .Values.credentials.remoteKeys }}
{{- if regexMatch "<<.*>>" $k }}
{{- fail (printf "credentials.remoteKeys contains a placeholder (%q) - fill it in before installing" $k) }}
{{- end }}
{{- end }}
{{- if not (has .Values.provider (list "aws" "azure")) }}
{{- fail "provider must be one of: aws, azure" }}
{{- end }}
{{- if and (eq .Values.provider "aws") (not .Values.aws.region) }}
{{- fail "aws.region is required when provider is aws" }}
{{- end }}
{{- if and (eq .Values.provider "azure") (not .Values.azure.vaultUrl) }}
{{- fail "azure.vaultUrl is required when provider is azure" }}
{{- end }}
{{/* Azure injects nothing without the client id, so the job would start and
     fail at the identity step. Catch it at render time instead. */}}
{{- if and (eq .Values.provider "azure") (not .Values.serviceAccount.clientId) }}
{{- if not (hasKey .Values.serviceAccount.annotations "azure.workload.identity/client-id") }}
{{- fail "serviceAccount.clientId is required when provider is azure (the managed identity's client id)" }}
{{- end }}
{{- end }}
{{/* roleArn and clientId are mutually exclusive: setting both means the
     intended identity is ambiguous. */}}
{{- if and .Values.serviceAccount.roleArn .Values.serviceAccount.clientId }}
{{- fail "set either serviceAccount.roleArn (EKS IRSA) or serviceAccount.clientId (Azure), not both" }}
{{- end }}
{{- if and .Values.credentials.enabled (not .Values.credentials.remoteKeys) }}
{{- fail "credentials.remoteKeys must list at least one remote item when credentials.enabled is true" }}
{{- end }}
{{- if and (or .Values.earKey.manage .Values.earKey.backup) (not .Values.earKey.remoteKey) }}
{{- fail "earKey.remoteKey is required when earKey.manage or earKey.backup is true" }}
{{- end }}
{{/* Key Vault names allow [a-zA-Z0-9-] only, so an AWS-style path fails at
     runtime with an opaque 400. Catch it at render time instead. */}}
{{- if eq .Values.provider "azure" }}
{{- range $k := .Values.credentials.remoteKeys }}
{{- if not (regexMatch "^[a-zA-Z0-9-]{1,127}$" $k) }}
{{- fail (printf "credentials.remoteKeys: %q is not a valid Key Vault secret name (only letters, digits and hyphens)" $k) }}
{{- end }}
{{- end }}
{{- if and .Values.earKey.remoteKey (not (regexMatch "^[a-zA-Z0-9-]{1,127}$" .Values.earKey.remoteKey)) }}
{{- fail (printf "earKey.remoteKey: %q is not a valid Key Vault secret name (only letters, digits and hyphens)" .Values.earKey.remoteKey) }}
{{- end }}
{{- end }}
{{- end -}}

{{/* Deployments to roll. Defaults cover the standard release layout. */}}
{{- define "secretsmanager.restartTargets" -}}
{{- if .Values.credentials.restartTargets -}}
{{- join " " .Values.credentials.restartTargets -}}
{{- else -}}
{{- $n := .Values.credentials.nectedReleaseName -}}
{{- $t := .Values.credentials.temporalFullname -}}
{{- $out := list -}}
{{- range $svc := (list "nalanda" "vidhaan-router" "vidhaan-executer" "medha" "garuda") -}}
{{- $out = append $out (printf "%s-%s" $n $svc) -}}
{{- end -}}
{{- range $svc := (list "frontend" "history" "matching" "worker") -}}
{{- $out = append $out (printf "%s-%s" $t $svc) -}}
{{- end -}}
{{- join " " $out -}}
{{- end -}}
{{- end -}}

{{/* Env for the hook Job. */}}
{{- define "secretsmanager.env" -}}
- name: PROVIDER
  value: {{ .Values.provider | quote }}
- name: FAIL_OPEN
  value: {{ .Values.failOpen | quote }}
- name: SA_NAME
  value: {{ .Values.serviceAccount.name | quote }}
{{- if eq .Values.provider "aws" }}
- name: AWS_REGION
  value: {{ .Values.aws.region | quote }}
{{- with .Values.aws.endpoint }}
- name: SM_ENDPOINT
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- if eq .Values.provider "azure" }}
- name: AZURE_VAULT_URL
  value: {{ .Values.azure.vaultUrl | quote }}
{{- end }}
{{- if .Values.credentials.enabled }}
- name: CRED_SECRET
  value: {{ .Values.credentials.secret | quote }}
- name: CRED_REMOTE_KEYS
  value: {{ join " " .Values.credentials.remoteKeys | quote }}
- name: CRED_REQUIRED_KEYS
  value: {{ join " " .Values.credentials.requiredKeys | quote }}
{{- with .Values.credentials.aliases }}
- name: CRED_ALIASES
  value: {{ range $target, $source := . }}{{ $target }}={{ $source }} {{ end }}
{{- end }}
- name: RESTART_TARGETS
  value: {{ include "secretsmanager.restartTargets" . | quote }}
{{- end }}
- name: EAR_MANAGE
  value: {{ .Values.earKey.manage | quote }}
- name: EAR_BACKUP
  value: {{ .Values.earKey.backup | quote }}
- name: EAR_OVERWRITE
  value: {{ .Values.earKey.overwrite | quote }}
- name: EAR_SECRET
  value: {{ .Values.earKey.secretName | quote }}
- name: EAR_KEY
  value: {{ .Values.earKey.secretKey | quote }}
{{- with .Values.earKey.remoteKey }}
- name: EAR_REMOTE
  value: {{ . | quote }}
{{- end }}
{{- end -}}

{{/* Pod spec for the hook Job. */}}
{{- define "secretsmanager.podSpec" -}}
serviceAccountName: {{ .Values.serviceAccount.name }}
restartPolicy: OnFailure
containers:
  - name: sync
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    command: ["/bin/sh", "/opt/secretsmanager/run.sh"]
    env:
      {{- include "secretsmanager.env" . | nindent 6 }}
    {{- with .Values.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    volumeMounts:
      - name: scripts
        mountPath: /opt/secretsmanager
        readOnly: true
volumes:
  - name: scripts
    configMap:
      name: {{ include "secretsmanager.fullname" . }}-scripts
      defaultMode: 0555
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Azure's webhook injects nothing without this label on the POD template. */}}
{{- define "secretsmanager.podLabels" -}}
{{- include "secretsmanager.labels" . }}
{{- with .Values.podLabels }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- if eq .Values.provider "azure" }}
azure.workload.identity/use: "true"
{{- end }}
{{- end -}}
