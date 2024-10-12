{{/*
Expand the name of the chart.
*/}}
{{- define "dashboard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "dashboard.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "dashboard.fullname" -}}
{{- $name := default .Chart.Name }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}


{{/*
Common labels
*/}}
{{- define "dashboard.labels" -}}
helm.sh/chart: {{ include "dashboard.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{ include "dashboard.selectorLabels" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.openshift.io/runtime: {{ .Values.languageFramework }}

{{- end }}

{{/*
Selector labels
*/}}
{{- define "dashboard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dashboard.fullname" . }}
{{- end }}