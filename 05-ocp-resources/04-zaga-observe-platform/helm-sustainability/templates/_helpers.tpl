{{/*
Expand the name of the chart.
*/}}
{{- define "sustainability.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "sustainability.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "sustainability.fullname" -}}
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
{{- define "sustainability.labels" -}}
helm.sh/chart: {{ include "sustainability.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Release.Name }}
{{ include "sustainability.selectorLabels" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.openshift.io/runtime: {{ .Values.languageFramework }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sustainability.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sustainability.fullname" . }}
{{- end }}
