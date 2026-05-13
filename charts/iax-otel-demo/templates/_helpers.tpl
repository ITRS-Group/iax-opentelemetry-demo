{{/*
Expand the name of the chart.
*/}}
{{- define "iax-otel-demo.name" -}}
{{- default .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "iax-otel-demo.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every Kubernetes object.
*/}}
{{- define "iax-otel-demo.labels" -}}
helm.sh/chart: {{ include "iax-otel-demo.chart" . }}
{{ include "iax-otel-demo.selectorLabels" . }}
{{ include "iax-otel-demo.workloadLabels" . }}
app.kubernetes.io/part-of: iax-otel-demo
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Workload (Pod) labels — version and component name.
*/}}
{{- define "iax-otel-demo.workloadLabels" -}}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- if .name }}
app.kubernetes.io/component: {{ .name }}
app.kubernetes.io/name: {{ .name }}
{{- end }}
{{- end }}

{{/*
Selector labels — minimal set for matching Pods to Services/Deployments.
*/}}
{{- define "iax-otel-demo.selectorLabels" -}}
{{- if .name }}
opentelemetry.io/name: {{ .name }}
{{- end }}
{{- end }}

{{/*
Merge environment variables: base list + overrides.
Overrides replace entries with the same name; extras are appended.
*/}}
{{- define "iax-otel-demo.envOverridden" -}}
{{- $mergedEnvs := list }}
{{- $envOverrides := default (list) .envOverrides }}
{{- range .env }}
{{-   $currentEnv := . }}
{{-   $hasOverride := false }}
{{-   range $envOverrides }}
{{-     if eq $currentEnv.name .name }}
{{-       $mergedEnvs = append $mergedEnvs . }}
{{-       $envOverrides = without $envOverrides . }}
{{-       $hasOverride = true }}
{{-     end }}
{{-   end }}
{{-   if not $hasOverride }}
{{-     $mergedEnvs = append $mergedEnvs $currentEnv }}
{{-   end }}
{{- end }}
{{- $mergedEnvs = concat $mergedEnvs $envOverrides }}
{{- mustToJson $mergedEnvs }}
{{- end }}

{{/*
Resolve the full image string for a component.
When imageOverride.repository is set the component uses a standalone image
(e.g. "postgres", "ghcr.io/open-feature/flagd") — no component-name suffix.
Otherwise the default registry is combined with the component name.
*/}}
{{- define "iax-otel-demo.image" -}}
{{- if and .imageOverride .imageOverride.repository -}}
{{-   $tag := .imageOverride.tag | default .defaultValues.image.tag -}}
{{-   printf "%s:%s" .imageOverride.repository $tag -}}
{{- else -}}
{{-   $tag := .defaultValues.image.tag -}}
{{-   if and .imageOverride .imageOverride.tag -}}
{{-     $tag = .imageOverride.tag -}}
{{-   end -}}
{{-   printf "%s/%s:%s" .defaultValues.image.repository .name $tag -}}
{{- end -}}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "iax-otel-demo.serviceAccountName" -}}
{{- if .serviceAccount.create }}
{{- default (include "iax-otel-demo.name" .) .serviceAccount.name }}
{{- else }}
{{- default "default" .serviceAccount.name }}
{{- end }}
{{- end }}
