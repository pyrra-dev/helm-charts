{{/*
Container definition for the Pyrra operator (kubernetes mode).
*/}}
{{- define "pyrra.container.kubernetes" -}}
- name: {{ .Chart.Name }}-kubernetes
  securityContext:
    {{- toYaml .Values.securityContext | nindent 4 }}
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  args:
    - kubernetes
    {{- if .Values.genericRules.enabled }}
    - --generic-rules
    {{- end }}
    {{- if and .Values.validatingWebhookConfiguration.enabled ($.Capabilities.APIVersions.Has "cert-manager.io/v1") }}
    - --disable-webhooks=false
    {{- end }}
    {{- if .Values.operatorMetricsAddress }}
    - --metrics-addr={{ .Values.operatorMetricsAddress }}
    {{- end }}
    {{- with .Values.extraKubernetesArgs }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  resources:
    {{- toYaml .Values.operator.resources | nindent 4 }}
  {{- if and .Values.validatingWebhookConfiguration.enabled ($.Capabilities.APIVersions.Has "cert-manager.io/v1") }}
  volumeMounts:
    - mountPath: /tmp/k8s-webhook-server/serving-certs
      name: certs
  {{- end }}
  ports:
    - name: op-metrics
      containerPort: {{ include "pyrra.operatorMetricsPort" . }}
    - name: webhooks
      containerPort: 9443
{{- end }}

{{/*
Container definition for the Pyrra API server.
*/}}
{{- define "pyrra.container.api" -}}
- name: {{ .Chart.Name }}
  securityContext:
    {{- toYaml .Values.securityContext | nindent 4 }}
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  args:
    - api
    - --prometheus-url={{ .Values.prometheusUrl }}
    - --api-url=http://localhost:9444
    {{- if .Values.prometheusExternalUrl }}
    - --prometheus-external-url={{ .Values.prometheusExternalUrl }}
    {{- end }}
    {{- if .Values.routePrefix }}
    - --route-prefix={{ .Values.routePrefix }}
    {{- end }}
    {{- with .Values.extraApiArgs }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  ports:
    - name: http
      containerPort: 9099
  {{- if .Values.extraApiVolumeMounts }}
  volumeMounts:
    {{- with .Values.extraApiVolumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end }}
