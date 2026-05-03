{{/*
=============================================================================
_helpers.tpl — Macros reutilizáveis
=============================================================================
*/}}

{{- define "hello.name" -}}
{{- printf "hello-%s" .Values.version }}
{{- end }}

{{- define "hello.labels" -}}
app.kubernetes.io/name:       hello-service
app.kubernetes.io/instance:   {{ include "hello.name" . }}
app.kubernetes.io/version:    {{ .Values.version }}
app.kubernetes.io/managed-by: argocd
traffic.role:                 {{ if .Values.shadow }}shadow{{ else }}real{{ end }}
cluster.name:                 {{ .Values.cluster }}
{{- end }}

{{- define "hello.selectorLabels" -}}
app:     hello-service
version: {{ .Values.version }}
{{- end }}

{{- define "hello.annotations" -}}
deploy.timestamp: {{ now | date "2006-01-02T15:04:05Z" | quote }}
deploy.image:     {{ .Values.image | quote }}
deploy.shadow:    {{ .Values.shadow | quote }}
deploy.cluster:   {{ .Values.cluster | quote }}
deploy.weight:    {{ .Values.weight | quote }}
{{- end }}
