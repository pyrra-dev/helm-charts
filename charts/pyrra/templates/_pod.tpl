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
    {{- if .Values.operator.leaderElection.enabled }}
    - --enable-leader-election
    - --leader-election-namespace={{ .Values.operator.leaderElection.namespace | default (include "pyrra.namespace" .) }}
    {{- end }}
    {{- with .Values.extraKubernetesArgs }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  resources:
    {{- toYaml .Values.operator.resources | nindent 4 }}
  {{- with .Values.operator.resizePolicy }}
  resizePolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
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
    {{- if .Values.openshift.enabled }}
    - --tls-client-ca-file=/etc/tls/openshift-service-ca.crt/service-ca.crt
    - --prometheus-bearer-token-path=/var/run/secrets/kubernetes.io/serviceaccount/token
    {{- end }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  {{- with .Values.resizePolicy }}
  resizePolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  ports:
    - name: http
      containerPort: 9099
  {{- if or .Values.openshift.enabled .Values.extraApiVolumeMounts }}
  volumeMounts:
    {{- if .Values.openshift.enabled }}
    - name: openshift-service-ca-crt
      mountPath: /etc/tls/openshift-service-ca.crt
    {{- end }}
    {{- with .Values.extraApiVolumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Container definition for the OpenShift OAuth proxy sidecar.
*/}}
{{- define "pyrra.container.openshiftOauthProxy" -}}
{{- $oauth := .Values.openshift.oauth -}}
{{- $port := include "pyrra.openshiftOauthPort" . -}}
- name: oauth-proxy
  resources:
    {{- toYaml $oauth.resources | nindent 4 }}
  securityContext:
    {{- toYaml $oauth.securityContext | nindent 4 }}
  image: {{ $oauth.image }}
  imagePullPolicy: IfNotPresent
  ports:
    {{- if $oauth.tls }}
    - name: oauth-https
      containerPort: {{ $port }}
      protocol: TCP
    {{- else }}
    - name: oauth-http
      containerPort: {{ $port }}
      protocol: TCP
    {{- end }}
  volumeMounts:
    - name: {{ include "pyrra.fullname" . }}
      mountPath: /etc/proxy/secrets/session_secret
      subPath: session_secret
    - name: {{ include "pyrra.fullname" . }}-injected-certs
      mountPath: /etc/proxy/certs
    {{- if $oauth.tls }}
    - name: {{ include "pyrra.fullname" . }}-tls
      mountPath: /etc/tls/private
    {{- end }}
  args:
    - "-provider=openshift"
    - "-pass-basic-auth=false"
    {{- if $oauth.tls }}
    - "-https-address=:{{ $port }}"
    - "-http-address="
    {{- else }}
    - "-http-address=:{{ $port }}"
    {{- end }}
    {{- range $oauth.emailDomains }}
    - "-email-domain={{ . }}"
    {{- end }}
    - "-upstream=http://localhost:9099"
    - "-client-secret-file=/var/run/secrets/kubernetes.io/serviceaccount/token"
    - "-cookie-secret-file=/etc/proxy/secrets/session_secret"
    - "-openshift-service-account={{ include "pyrra.fullname" . }}"
    - "-openshift-ca=/etc/pki/tls/cert.pem"
    - "-openshift-ca=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    - "-openshift-ca=/etc/proxy/certs/ca-bundle.crt"
    {{- if $oauth.tls }}
    - "-tls-cert=/etc/tls/private/tls.crt"
    - "-tls-key=/etc/tls/private/tls.key"
    {{- end }}
    {{- with $oauth.extraArgs }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}
