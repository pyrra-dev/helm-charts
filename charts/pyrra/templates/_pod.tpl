{{/*
Container definition for the Pyrra operator (kubernetes mode).
*/}}
{{- define "pyrra.container.kubernetes" -}}
{{- $mimir := .Values.mimir -}}
{{- $mimirAuth := $mimir.basicAuth -}}
{{- if and $mimirAuth.password $mimirAuth.existingSecret }}
{{- fail "pyrra: mimir.basicAuth.password and mimir.basicAuth.existingSecret are mutually exclusive" }}
{{- end }}
{{- if and (not $mimir.url) (or $mimirAuth.username $mimirAuth.password $mimirAuth.existingSecret $mimir.writeAlertingRules) }}
{{- fail "pyrra: mimir.* is configured but mimir.url is empty, so the whole Mimir integration stays off" }}
{{- end }}
{{- if and $mimir.url (not (has $mimir.deploymentMode (list "standalone" "distributed"))) }}
{{- fail (printf "pyrra: mimir.deploymentMode must be either standalone or distributed, got %q" $mimir.deploymentMode) }}
{{- end }}
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
    {{- if .Values.externalUrl }}
    - --external-url={{ .Values.externalUrl }}
    {{- end }}
    {{- if $mimir.url }}
    - --mimir-url={{ $mimir.url }}
    - --mimir-prometheus-prefix={{ $mimir.prometheusPrefix }}
    - --mimir-deployment-mode={{ $mimir.deploymentMode }}
    {{- if $mimir.writeAlertingRules }}
    - --mimir-write-alerting-rules
    {{- end }}
    {{- with ($mimir.orgId | default .Values.mimirOrgId) }}
    - --mimir-org-id={{ . }}
    {{- end }}
    {{- with $mimirAuth.username }}
    - --mimir-basic-auth-username={{ . }}
    {{- end }}
    {{- if include "pyrra.mimirBasicAuthEnabled" . }}
    - --mimir-basic-auth-password=$(PYRRA_MIMIR_BASIC_AUTH_PASSWORD)
    {{- end }}
    {{- end }}
    {{- with .Values.extraKubernetesArgs }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- if include "pyrra.mimirBasicAuthEnabled" . }}
  env:
    - name: PYRRA_MIMIR_BASIC_AUTH_PASSWORD
      valueFrom:
        secretKeyRef:
          name: {{ include "pyrra.mimirBasicAuthSecretName" . }}
          key: {{ include "pyrra.mimirBasicAuthSecretKey" . }}
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
{{- if and .Values.prometheusExternalUrl .Values.grafanaExternalUrl }}
{{- fail "pyrra: set only one of prometheusExternalUrl or grafanaExternalUrl, not both" }}
{{- end }}
{{- if and .Values.grafanaExternalUrl (not .Values.grafanaExternalDatasourceId) }}
{{- fail "pyrra: grafanaExternalDatasourceId is required when grafanaExternalUrl is set" }}
{{- end }}
{{- if and .Values.grafanaExternalDatasourceId (not .Values.grafanaExternalUrl) }}
{{- fail "pyrra: grafanaExternalDatasourceId requires grafanaExternalUrl to be set" }}
{{- end }}
{{- if and (not .Values.openshift.enabled) (or .Values.openshift.oauth.enabled .Values.openshift.route.enabled) }}
{{- fail "pyrra: openshift.oauth/route are configured but openshift.enabled is false, so the whole OpenShift integration stays off" }}
{{- end -}}
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
    {{- if .Values.prometheusBasicAuthUsername }}
    - --prometheus-basic-auth-username={{ .Values.prometheusBasicAuthUsername }}
    {{- end }}
    {{- if .Values.prometheusBearerTokenPath }}
    - --prometheus-bearer-token-path={{ .Values.prometheusBearerTokenPath }}
    {{- end }}
    {{- if .Values.mimirOrgId }}
    - --mimir-org-id={{ .Values.mimirOrgId }}
    {{- end }}
    {{- if .Values.grafanaExternalUrl }}
    - --grafana-external-url={{ .Values.grafanaExternalUrl }}
    {{- end }}
    {{- if .Values.grafanaExternalOrgId }}
    - --grafana-external-org-id={{ .Values.grafanaExternalOrgId }}
    {{- end }}
    {{- if .Values.grafanaExternalDatasourceId }}
    - --grafana-external-datasource-id={{ .Values.grafanaExternalDatasourceId }}
    {{- end }}
    {{- if .Values.routePrefix }}
    - --route-prefix={{ .Values.routePrefix }}
    {{- end }}
    {{- if .Values.openshift.enabled }}
    - --tls-client-ca-file=/etc/tls/openshift-service-ca.crt/service-ca.crt
    {{- if not .Values.prometheusBearerTokenPath }}
    - --prometheus-bearer-token-path=/var/run/secrets/kubernetes.io/serviceaccount/token
    {{- end }}
    {{- end }}
    {{- with .Values.extraApiArgs }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  resources:
    {{- toYaml .Values.resources | nindent 4 }}
  {{- with .Values.resizePolicy }}
  resizePolicy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  ports:
    - name: http
      containerPort: {{ include "pyrra.apiPort" . }}
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
{{- if or (not $oauth.image.repository) (not $oauth.image.tag) -}}
{{- fail "openshift.oauth.image.repository and openshift.oauth.image.tag are required when openshift.oauth.enabled=true" -}}
{{- end -}}
{{- if not $oauth.emailDomains -}}
{{- fail "openshift.oauth.emailDomains is required when openshift.oauth.enabled=true — without an -email-domain flag the proxy rejects every login while staying Ready" -}}
{{- end -}}
{{- if and .Values.openshift.route.enabled (not .Values.serviceAccount.create) -}}
{{- fail "pyrra: the OAuth redirect annotation lives on the chart-managed ServiceAccount, so openshift.oauth.enabled with openshift.route.enabled requires serviceAccount.create=true" -}}
{{- end -}}
- name: oauth-proxy
  resources:
    {{- toYaml $oauth.resources | nindent 4 }}
  securityContext:
    {{- toYaml $oauth.securityContext | nindent 4 }}
  image: "{{ $oauth.image.repository }}:{{ $oauth.image.tag }}"
  imagePullPolicy: {{ $oauth.image.pullPolicy }}
  ports:
    - name: {{ include "pyrra.openshiftOauthPortName" . }}
      containerPort: {{ $oauth.port }}
      protocol: TCP
  volumeMounts:
    - name: session-secret
      mountPath: /etc/proxy/secrets
      readOnly: true
    - name: injected-certs
      mountPath: /etc/proxy/certs
      readOnly: true
    {{- if $oauth.tls }}
    - name: proxy-tls
      mountPath: /etc/tls/private
      readOnly: true
    {{- end }}
  args:
    - "-provider=openshift"
    - "-pass-basic-auth=false"
    {{- if $oauth.tls }}
    - "-https-address=:{{ $oauth.port }}"
    - "-http-address="
    {{- else }}
    - "-http-address=:{{ $oauth.port }}"
    {{- end }}
    {{- range $oauth.emailDomains }}
    - "-email-domain={{ . }}"
    {{- end }}
    {{- with $oauth.sar }}
    - '-openshift-sar={{ toJson . }}'
    {{- end }}
    - "-upstream=http://localhost:{{ include "pyrra.apiPort" . }}"
    - "-client-secret-file=/var/run/secrets/kubernetes.io/serviceaccount/token"
    - "-cookie-secret-file=/etc/proxy/secrets/session_secret"
    - "-openshift-service-account={{ include "pyrra.serviceAccountName" . }}"
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
  livenessProbe:
    httpGet:
      path: /oauth/healthz
      port: {{ include "pyrra.openshiftOauthPortName" . }}
      scheme: {{ if $oauth.tls }}HTTPS{{ else }}HTTP{{ end }}
  readinessProbe:
    httpGet:
      path: /oauth/healthz
      port: {{ include "pyrra.openshiftOauthPortName" . }}
      scheme: {{ if $oauth.tls }}HTTPS{{ else }}HTTP{{ end }}
{{- end }}
