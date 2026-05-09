{{- define "bookstore.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "bookstore.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "bookstore.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "bookstore.labels" -}}
app.kubernetes.io/name: {{ include "bookstore.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "bookstore.selectorLabels" -}}
app.kubernetes.io/name: {{ include "bookstore.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}