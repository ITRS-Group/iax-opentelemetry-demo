{{/*
Build the merged env var list for a component pod.
- Merges default env (when useDefault.env is true) with component env.
- Pulls out OTEL_RESOURCE_ATTRIBUTES so it can be appended last.
- Appends OTEL_RESOURCE_ATTRIBUTES_EXTRA values to OTEL_RESOURCE_ATTRIBUTES.
*/}}
{{- define "iax-otel-demo.pod.env" -}}
{{- $resourceAttributesEnv := dict }}
{{- $allEnvs := list }}

{{- if .useDefault.env }}
{{-   $defaultEnvs := include "iax-otel-demo.envOverridden" (dict "env" .defaultValues.env "envOverrides" .defaultValues.envOverrides) | mustFromJson }}
{{-   range $defaultEnvs }}
{{-     if eq .name "OTEL_RESOURCE_ATTRIBUTES" }}
{{-       $resourceAttributesEnv = . }}
{{-     else }}
{{-       $allEnvs = append $allEnvs . }}
{{-     end }}
{{-   end }}
{{- end }}

{{- if or .env .envOverrides }}
{{-   $localEnvs := include "iax-otel-demo.envOverridden" . | mustFromJson }}
{{-   range $localEnvs }}
{{-     if eq .name "OTEL_RESOURCE_ATTRIBUTES" }}
{{-       $resourceAttributesEnv = . }}
{{-     else if and $resourceAttributesEnv (eq .name "OTEL_RESOURCE_ATTRIBUTES_EXTRA") }}
{{-       $newValue := (printf "%s,%s" (get $resourceAttributesEnv "value") .value) }}
{{-       $resourceAttributesEnv = dict "name" "OTEL_RESOURCE_ATTRIBUTES" "value" $newValue }}
{{-     else }}
{{-       $allEnvs = append $allEnvs . }}
{{-     end }}
{{-   end }}
{{- end }}

{{- if $resourceAttributesEnv }}
{{-   $allEnvs = append $allEnvs $resourceAttributesEnv }}
{{- end }}

{{- tpl (toYaml $allEnvs) . }}
{{- end }}

{{/*
Build the ports list for a component container.
*/}}
{{- define "iax-otel-demo.pod.ports" -}}
{{- if .ports }}
{{-   range $port := .ports }}
- containerPort: {{ $port.value }}
  name: {{ $port.name }}
{{-   end }}
{{- end }}
{{- if .service }}
{{-   if .service.port }}
- containerPort: {{ .service.port }}
  name: service
{{-   end }}
{{- end }}
{{- end }}
