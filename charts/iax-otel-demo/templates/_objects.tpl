{{/*
Component Deployment template.
*/}}
{{- define "iax-otel-demo.deployment" }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .name }}
  labels:
    {{- include "iax-otel-demo.labels" . | nindent 4 }}
spec:
  replicas: {{ .replicas | default .defaultValues.replicas }}
  selector:
    matchLabels:
      {{- include "iax-otel-demo.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "iax-otel-demo.selectorLabels" . | nindent 8 }}
        {{- include "iax-otel-demo.workloadLabels" . | nindent 8 }}
        {{- if .podLabels }}
        {{- toYaml .podLabels | nindent 8 }}
        {{- end }}
      {{- if .podAnnotations }}
      annotations:
        {{- toYaml .podAnnotations | nindent 8 }}
      {{- end }}
    spec:
      {{- if or .defaultValues.image.pullSecrets ((.imageOverride).pullSecrets) }}
      imagePullSecrets:
        {{- ((.imageOverride).pullSecrets) | default .defaultValues.image.pullSecrets | toYaml | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "iax-otel-demo.serviceAccountName" . }}
      {{- $schedulingRules := .schedulingRules | default dict }}
      {{- if or .defaultValues.schedulingRules.nodeSelector $schedulingRules.nodeSelector }}
      nodeSelector:
        {{- $schedulingRules.nodeSelector | default .defaultValues.schedulingRules.nodeSelector | toYaml | nindent 8 }}
      {{- end }}
      {{- if or .defaultValues.schedulingRules.affinity $schedulingRules.affinity }}
      affinity:
        {{- $schedulingRules.affinity | default .defaultValues.schedulingRules.affinity | toYaml | nindent 8 }}
      {{- end }}
      {{- if or .defaultValues.schedulingRules.tolerations $schedulingRules.tolerations }}
      tolerations:
        {{- $schedulingRules.tolerations | default .defaultValues.schedulingRules.tolerations | toYaml | nindent 8 }}
      {{- end }}
      {{- if or .defaultValues.podSecurityContext .podSecurityContext }}
      securityContext:
        {{- .podSecurityContext | default .defaultValues.podSecurityContext | toYaml | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .name }}
          image: {{ include "iax-otel-demo.image" . }}
          imagePullPolicy: {{ ((.imageOverride).pullPolicy) | default .defaultValues.image.pullPolicy }}
          {{- if .command }}
          command:
            {{- .command | toYaml | nindent 12 }}
          {{- end }}
          {{- if or .ports .service }}
          ports:
            {{- include "iax-otel-demo.pod.ports" . | nindent 12 }}
          {{- end }}
          env:
            {{- include "iax-otel-demo.pod.env" . | nindent 12 }}
          {{- if .resources }}
          resources:
            {{- .resources | toYaml | nindent 12 }}
          {{- end }}
          {{- if or .defaultValues.securityContext .securityContext }}
          securityContext:
            {{- .securityContext | default .defaultValues.securityContext | toYaml | nindent 12 }}
          {{- end }}
          {{- if .livenessProbe }}
          livenessProbe:
            {{- .livenessProbe | toYaml | nindent 12 }}
          {{- end }}
          {{- if .readinessProbe }}
          readinessProbe:
            {{- .readinessProbe | toYaml | nindent 12 }}
          {{- end }}
          volumeMounts:
          {{- range .mountedConfigMaps }}
            - name: {{ .name | lower }}
              mountPath: {{ .mountPath }}
              {{- if .subPath }}
              subPath: {{ .subPath }}
              {{- end }}
          {{- end }}
      volumes:
        {{- range .mountedConfigMaps }}
        - name: {{ .name | lower }}
          configMap:
            name: {{ $.name }}-{{ .name | lower }}
        {{- end }}
{{- end }}

{{/*
Component Service template.
Only rendered when at least one port is defined.
*/}}
{{- define "iax-otel-demo.service" }}
{{- $hasPorts := false }}
{{- if .ports }}{{ $hasPorts = true }}{{ end }}
{{- if and .service .service.port }}{{ $hasPorts = true }}{{ end }}
{{- if $hasPorts }}
{{- $service := .service | default dict }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  labels:
    {{- include "iax-otel-demo.labels" . | nindent 4 }}
  {{- with $service.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ $service.type | default "ClusterIP" }}
  ports:
    {{- if .ports }}
    {{- range .ports }}
    - port: {{ .value }}
      name: {{ .name }}
      targetPort: {{ .value }}
    {{- end }}
    {{- end }}
    {{- if and .service .service.port }}
    - port: {{ .service.port }}
      name: tcp-service
      targetPort: {{ .service.port }}
    {{- end }}
  selector:
    {{- include "iax-otel-demo.selectorLabels" . | nindent 4 }}
{{- end }}
{{- end }}

{{/*
Component ConfigMap template — renders data from mountedConfigMaps entries.
*/}}
{{- define "iax-otel-demo.configmap" }}
{{- range .mountedConfigMaps }}
{{- if .data }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $.name }}-{{ .name | lower }}
  labels:
    {{- include "iax-otel-demo.labels" $ | nindent 4 }}
data:
  {{- .data | toYaml | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
