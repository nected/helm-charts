{{/*
Expand the name of the chart.
*/}}

{{- define "common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "common.fullname" -}}
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
{{- define "common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "common.labels" -}}
helm.sh/chart: {{ include "common.chart" . }}
{{ include "common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "common.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "common.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Create pod annotations
*/}}
{{- define "common.podAnnotations" -}}
{{- with .Values.annotations }}
{{- toYaml . }}
{{- end }}
{{- end }}


{{/*
Create autosetup pod annotations from values  and include pod annotations
*/}}
{{- define "common.autoSetupPodAnnotations" -}}
{{- if .Values.autoSetup.enabled }}
{{- include "common.podAnnotations" . }}
{{- with .Values.autoSetup.annotations }}
{{- toYaml . -}}
{{- end -}}
{{- end }}
{{- end }}

{{/*
Create autosetup pod labels from values and include pod labels
*/}}
{{- define "common.autoSetupPodAnnotationsHook" -}}
{{- if .Values.autoSetup.enabled }}
{{- include "common.autoSetupPodAnnotations" . -}}
{{ else }}
{{- include "common.podAnnotations" . -}}
{{ end }}
"helm.sh/hook": post-install
"helm.sh/hook-weight": "0"
{{- if not .Values.autoSetup.debug }}
"helm.sh/hook-delete-policy": hook-succeeded,hook-failed
{{- end -}}
{{- end -}}


{{/*
Common configMap data generator
*/}}

{{- define "common.configMapData" -}}
{{- if .Values.mountConfigMap }}
data:
  envFile: |
  {{- range $key, $value := .Values.envVars }}
  {{ $key }}={{ $value}}
  {{- end }}
{{- else }}
data:
  {{- toYaml .Values.envVars }}
{{- end }}
{{- end }}