{{/*
Expand the name of the chart.
*/}}
{{- define "nalanda.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nalanda.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nalanda.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nalanda.labels" -}}
helm.sh/chart: {{ include "nalanda.chart" . }}
{{ include "nalanda.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nalanda.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nalanda.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nalanda.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nalanda.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Create pod annotations
*/}}
{{- define "nalanda.podAnnotations" -}}
{{- with .Values.annotations }}
{{- toYaml . }}
{{- end }}
{{- end }}


{{/*
Create autosetup pod annotations from values  and include pod annotations
*/}}
{{- define "nalanda.autoSetupPodAnnotations" -}}
{{- if .Values.autoSetup.enabled }}
{{- include "nalanda.podAnnotations" . }}
{{ toYaml .Values.autoSetup.annotations }}
{{- end }}
{{- end }}

{{/*
Create autosetup pod labels from values and include pod labels
*/}}
{{- define "nalanda.autoSetupPodAnnotationsHook" -}}
{{- include "nalanda.podAnnotations" . }}
{{- if .Values.autoSetup.enabled }}
{{- include "nalanda.autoSetupPodAnnotations" . }}
"helm.sh/hook": pre-install
"helm.sh/hook-weight": "0"
{{- if not .Values.autoSetup.debug }}
"helm.sh/hook-delete-policy": hook-succeeded,hook-failed
{{- end }}
{{- end }}
{{- end }}

{{/*
Create nalanda default configmap from values.config
*/}}
{{- define "nalanda.defaultConfig" -}}
{{- with .Values.defaultConfig }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Create nalanda default configmap from values.config
*/}}
{{- define "nalanda.staticConfig" -}}
SERVER_HOST: 0.0.0.0
SERVER_PORT: 8001
ASSETS_BASE_URL: https://assets.dev.nected.io
KONARK_RESET_PASSWORD_PATH: /reset-password/
KONARK_EMAIL_VERIFICATION_PATH: /verify/signup/email/
KONARK_WORKSPACE_INVITATION_PATH: /verify/workspace/invitation/
KONARK_OAUTH_REDIRECT_PATH: /oauth/redirect
NECTED_USER_EMAIL: dev@nected.ai
NECTED_USER_PASSWORD: password
MASTER_DB_NAME: nected
MASTER_DB_USER: nected
MASTER_DB_CONNS_POOL_ENABLE: true
MASTER_DB_MAX_IDLE_CONNS: 5
MASTER_DB_MAX_OPEN_CONNS: 10
MASTER_DB_CONN_MAX_LIFETIME: 1h
MASTER_DB_CONN_MAX_IDLE_TIME: 30m
REDIS_DATABASE: 0
ELASTIC_ADUIT_PATTERN: audit-*
ELASTIC_ENTITY_AUDIT_INDEX: audit-log-nalanda
VIDHAAN_INTERNAL_API_PATH: /nected/test
VIDHAAN_EXTERNAL_API_PATH: /nected
VIDHAAN_HEALTH_API_PATH: /nected/health
VIDHAAN_EXECUTION_LOGS_API_PATH: /nected/execution-log
VIDHAAN_SCHEDULE_API_PATH: /nected/schedule
VIDHAAN_HEADER_AGENT_KEY_NAME: vidhaan-agent-key
VIDHAAN_AUTH_HEADER_KEY_NAME: nected-api-key
VIDHAAN_HEADER_WORKSPACE_KEY_NAME: vidhaan-workspace-key
LICENSE_KEY_PATH: /tmp/license/private.key
{{- end }}

{{/*
Create nalanda configmap from values.envVars
*/}}
{{- define "nalanda.configMap" -}}
{{- with .Values.envVars }}
{{- toYaml . }}
{{- end }}
{{- end }}






