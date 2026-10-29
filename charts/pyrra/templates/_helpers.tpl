{{/*
Expand the name of the chart.
*/}}
{{- define "pyrra.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pyrra.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pyrra.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pyrra.labels" -}}
helm.sh/chart: {{ include "pyrra.chart" . }}
{{ include "pyrra.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/component: metrics
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.additionalLabels }}
{{ toYaml .Values.additionalLabels }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pyrra.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pyrra.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "pyrra.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pyrra.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace to deploy resources into.
*/}}
{{- define "pyrra.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Operator metrics port
*/}}
{{- define "pyrra.operatorMetricsPort" -}}
{{ (split ":" .Values.operatorMetricsAddress)._1 }}
{{- end }}

{{/*
Whether the operator needs a Mimir basic auth password from a Secret at all.
*/}}
{{- define "pyrra.mimirBasicAuthEnabled" -}}
{{- if and .Values.mimir.url (or .Values.mimir.basicAuth.password .Values.mimir.basicAuth.existingSecret) -}}true{{- end -}}
{{- end }}

{{/*
Whether this chart renders the Mimir basic auth Secret itself, as opposed to the
user bringing their own via existingSecret.
*/}}
{{- define "pyrra.mimirBasicAuthChartManaged" -}}
{{- if and .Values.mimir.url .Values.mimir.basicAuth.password (not .Values.mimir.basicAuth.existingSecret) -}}true{{- end -}}
{{- end }}

{{/*
Name of the Secret holding the Mimir basic auth password: the user-provided
existingSecret when set, otherwise the one this chart renders.
*/}}
{{- define "pyrra.mimirBasicAuthSecretName" -}}
{{- if .Values.mimir.basicAuth.existingSecret -}}
{{- .Values.mimir.basicAuth.existingSecret -}}
{{- else -}}
{{ include "pyrra.fullname" . }}-mimir-basic-auth
{{- end -}}
{{- end }}

{{/*
Key inside that Secret. existingSecretKey only applies to a user-provided Secret;
the chart-rendered one always uses a fixed key.
*/}}
{{- define "pyrra.mimirBasicAuthSecretKey" -}}
{{- if .Values.mimir.basicAuth.existingSecret -}}
{{- .Values.mimir.basicAuth.existingSecretKey | default "mimir-basic-auth-password" -}}
{{- else -}}
mimir-basic-auth-password
{{- end -}}
{{- end }}

{{/*
Internal port the Pyrra API container listens on. Used both by the api
container's containerPort and by the OpenShift OAuth-proxy upstream URL.
*/}}
{{- define "pyrra.apiPort" -}}9099{{- end }}

{{/*
Name of the OAuth-proxy port. Ties together the container port, the Service
port, the Route targetPort and the probes — all of which match by name.
*/}}
{{- define "pyrra.openshiftOauthPortName" -}}
{{- if .Values.openshift.oauth.tls -}}oauth-https{{- else -}}oauth-http{{- end -}}
{{- end }}

{{/*
Whether this chart renders the OAuth-proxy session Secret itself, as opposed
to the user bringing their own via existingSecret.
*/}}
{{- define "pyrra.openshiftOauthSessionChartManaged" -}}
{{- if and .Values.openshift.enabled .Values.openshift.oauth.enabled (not .Values.openshift.oauth.existingSecret) -}}true{{- end -}}
{{- end }}

{{/*
OpenShift OAuth-proxy session Secret name. Resolves to the user-provided
existingSecret when set, otherwise to <fullname>-session.
*/}}
{{- define "pyrra.openshiftOauthSessionSecretName" -}}
{{- if .Values.openshift.oauth.existingSecret -}}
{{- .Values.openshift.oauth.existingSecret -}}
{{- else -}}
{{ include "pyrra.fullname" . }}-session
{{- end -}}
{{- end }}

{{/*
Key inside that Secret. existingSecretKey only applies to a user-provided Secret;
the chart-rendered one always uses a fixed key.
*/}}
{{- define "pyrra.openshiftOauthSessionSecretKey" -}}
{{- if .Values.openshift.oauth.existingSecret -}}
{{- .Values.openshift.oauth.existingSecretKey | default "session_secret" -}}
{{- else -}}
session_secret
{{- end -}}
{{- end }}
