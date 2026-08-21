# pyrra

SLO manager and alert generator

## Source Code

* <https://github.com/pyrra-dev/pyrra>

## Install

```bash
helm repo add pyrra https://pyrra-dev.github.io/helm-charts
helm repo update
helm install pyrra pyrra/pyrra
```

## Prometheus settings

Pyrra needs prometheus to work. You will need to specify that via prometheusUrl variable - default assumes you have default [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) deployed to "monitoring" namespace.
Additionally, you (most likely) will need to specify prometheusExternalUrl with URL to public-facing prometheus UI (ingress or whatever you're using), otherwise pyrra links to graphs will be broken

If Prometheus is behind authentication, set `prometheusBasicAuthUsername` and/or `prometheusBearerTokenPath`. Use `mimirOrgId` to query a specific tenant when Prometheus is fronted by Mimir.

`prometheusBearerTokenPath` points at a file inside the container, so mount the token from a Secret with `extraApiVolumes`/`extraApiVolumeMounts`:

```yaml
prometheusBearerTokenPath: /etc/pyrra/prometheus/token
extraApiVolumes:
  - name: prometheus-token
    secret:
      secretName: prometheus-token
extraApiVolumeMounts:
  - name: prometheus-token
    mountPath: /etc/pyrra/prometheus
    readOnly: true
```

There is no dedicated value for the HTTP basic-auth password: Pyrra only accepts it as a plain flag, which would land in the pod spec. If you need it, pass it through `extraApiArgs`.

## Mimir

There are two independent halves to running Pyrra against Mimir.

**Querying** is the API container's job and needs nothing but a tenant: point `prometheusUrl` at the Mimir query endpoint and set `mimirOrgId` to send the `X-Scope-OrgID` header.

**Provisioning rules** is the operator's job. Setting `mimir.url` switches it from creating `PrometheusRule` resources to writing recording rules directly to the Mimir Ruler. That single key gates the whole integration — there is no separate `enabled` flag, and any other `mimir.*` setting without a URL fails the render rather than being silently ignored.

```yaml
mimir:
  url: http://mimir-nginx.mimir.svc:80
  # standalone (default) or distributed — changes the endpoint Pyrra probes on startup
  deploymentMode: standalone
  # write alerting rules to the Ruler as well, not just recording rules
  writeAlertingRules: true
  orgId: my-tenant
  basicAuth:
    username: pyrra
    existingSecret: mimir-credentials
    existingSecretKey: password
```

`mimir.orgId` falls back to `mimirOrgId` when empty, since query and provisioning normally target the same tenant. Set it explicitly only if they differ.

**Set a tenant unless you know Mimir runs without multi-tenancy.** Pyrra treats it as optional and simply omits the `X-Scope-OrgID` header when empty. Mimir defaults `-auth.multitenancy-enabled` to `true`, and its Ruler config endpoints (`POST`/`DELETE` on `<prefix>/config/v1/rules/{namespace}`) sit behind the auth middleware — so rule provisioning fails without the header. The endpoints Pyrra probes at startup do not: `/api/v1/status/buildinfo` is registered with auth explicitly disabled, and `/ready` is not registered through Mimir's API layer at all, so it never reaches the middleware that wraps those routes. The operator therefore starts up healthy in either deployment mode and only fails once it reconciles the first `ServiceLevelObjective`. If Mimir runs with `-auth.multitenancy-enabled=false` it uses the `-auth.no-auth-tenant` pseudo-tenant (`anonymous` by default) and leaving this empty is correct.

### The basic-auth password

Pyrra accepts the password only as a plain flag value and reads no environment variables, so the chart never writes it into the pod spec directly. It always goes through a Secret, mounted as an environment variable that Kubernetes expands into the `--mimir-basic-auth-password` argument. You choose where that Secret comes from:

* **Bring your own** — set `basicAuth.existingSecret` (and `basicAuth.existingSecretKey` if the key differs from `mimir-basic-auth-password`). The password never passes through `values.yaml` or the Helm release, which is what you want with sealed-secrets, External Secrets Operator, or Vault.
* **Let the chart render one** — set `basicAuth.password` and the chart creates `<fullname>-mimir-basic-auth`. Convenient for a quick test, but the value still lives in your values file and in the release, readable via `helm get values`. The pod gets a `checksum/mimir-basic-auth` annotation so rotating the password actually restarts the operator.

The two are mutually exclusive; setting both fails the render rather than silently picking one.

## Linking alerts back to Pyrra

Set `externalUrl` to the public address of the Pyrra UI. The operator then adds a `pyrra_url` annotation to every generated alert, so an on-call responder can jump straight from a firing alert to the corresponding SLO.

## Grafana Explore instead of Prometheus

As an alternative to `prometheusExternalUrl`, set `grafanaExternalUrl` together with `grafanaExternalDatasourceId` to redirect graph links to Grafana Explore. `prometheusExternalUrl` and `grafanaExternalUrl` are mutually exclusive.

## Webhook Admissions Controller Validations (Optional)

Pyrra can be configured to validate SLOs and SLO groups using a webhook admission controller. This is an optional feature that can be enabled by setting the `validatingWebhookConfiguration.enabled` value to `true`. The webhook admission controller will validate SLOs when they are created or updated.
If the SLO object is invalid, the admission controller will reject the request and provide a reason for the failure. This requires cert-manager to be installed in the cluster. If cert-manager is not installed, the webhook admission controller will not be created.

## Grafana dashboards

Pyrra provides Grafana dashboards additionally to it's own UI.
The dashboards can be deployed using a ConfigMap and get's automatically [reloaded by a Grafana sidecar](https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-dashboards).

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| additionalLabels | object | `{}` |  |
| automountServiceAccountToken | bool | `true` | Whether to automount the service account token in the pod, enabled by default because Pyrra's kubernetes container requires Kubernetes API access. |
| dashboards.annotations | object | `{}` |  |
| dashboards.enabled | bool | `false` | enables Grafana dashboards being deployed via configmap |
| dashboards.extraLabels | object | `{}` |  |
| dashboards.label | string | `"grafana_dashboard"` | default value from the Grafana chart |
| dashboards.labelValue | string | `"1"` | default value from the Grafana chart |
| dashboards.namespace | string | `nil` |  |
| externalUrl | string | `""` | Public-facing URL of the Pyrra UI. When set, the operator adds a pyrra_url annotation with a direct link to the SLO to every generated alert. |
| extraApiArgs | list | `[]` | Extra args for Pyrra's API container |
| extraApiVolumeMounts | list | `[]` | Extra Volume Mounts for the container |
| extraApiVolumes | list | `[]` | Extra Volumes for the pod |
| extraKubernetesArgs | list | `[]` | Extra args for Pyrra's Kubernetes container |
| extraObjects | list | `[]` | Extra Kubernetes objects to deploy with the chart. Supports a list (or map) of manifests, each entry either a YAML map or a templated string rendered with tpl. |
| fullnameOverride | string | `""` | Overrides helm-generated chart fullname |
| genericRules.enabled | bool | `false` | enables generate Pyrra generic recording rules. Pyrra generates metrics with the same name for each SLO. |
| grafanaExternalDatasourceId | string | `""` | Grafana Explore Prometheus datasource ID. Required when grafanaExternalUrl is set. |
| grafanaExternalOrgId | string | `""` | Grafana Explore organization ID. Pyrra defaults to "1" when unset. |
| grafanaExternalUrl | string | `""` | URL to redirect users to the Grafana Explore page instead of Prometheus. Mutually exclusive with prometheusExternalUrl. |
| image.pullPolicy | string | `"IfNotPresent"` | Overrides pullpolicy |
| image.repository | string | `"ghcr.io/pyrra-dev/pyrra"` | Overrides the image repository |
| image.tag | string | `""` | Overrides the image tag |
| imagePullSecrets | list | `[]` | specifies pull secrets for image repository |
| ingress.annotations | object | `{}` | additional annotations for ingress |
| ingress.className | string | `""` | specifies ingress class name (ie nginx) |
| ingress.enabled | bool | `false` | enables ingress for server UI |
| ingress.hosts[0].host | string | `"chart-example.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.tls | list | `[]` |  |
| mimir.basicAuth.existingSecret | string | `""` | Name of an existing Secret holding the Mimir basic auth password, so the value never passes through Helm at all. Mutually exclusive with `password`. |
| mimir.basicAuth.existingSecretKey | string | `"mimir-basic-auth-password"` | Key inside `existingSecret` holding the password. Only applies to `existingSecret`; the chart-rendered Secret always uses the key `mimir-basic-auth-password`. |
| mimir.basicAuth.password | string | `""` | HTTP basic auth password for the Mimir API. The chart renders it into a `<fullname>-mimir-basic-auth` Secret rather than into the pod spec, but the value still passes through `values.yaml` and the Helm release. Prefer `existingSecret` in production. |
| mimir.basicAuth.username | string | `""` | HTTP basic auth username for the Mimir API |
| mimir.deploymentMode | string | `"standalone"` | Mimir deployment mode. One of `standalone`, `distributed`. |
| mimir.orgId | string | `""` | Mimir tenant ID (X-Scope-OrgID) the operator sends when provisioning rules. Falls back to `mimirOrgId` when empty, since query and provisioning usually target the same tenant. |
| mimir.prometheusPrefix | string | `"prometheus"` | Prefix of the Prometheus API in Mimir |
| mimir.url | string | `""` | URL to the Mimir API. When set, the operator provisions recording rules via the Mimir Ruler instead of creating PrometheusRule resources. This single key gates the whole Mimir integration — there is no separate `enabled` flag. Note that Pyrra checks the connection on startup and exits if Mimir is unreachable, so the operator will CrashLoopBackOff on a wrong URL. |
| mimir.writeAlertingRules | bool | `false` | Provision alerting rules to the Mimir Ruler as well, in addition to recording rules |
| mimirOrgId | string | `""` | Mimir tenant ID (X-Scope-OrgID) the API container sends when querying Prometheus behind Mimir |
| nameOverride | string | `""` | overrides chart name |
| namespaceOverride | string | `""` | Overrides the namespace for all resources (defaults to .Release.Namespace) |
| nodeSelector | object | `{}` | node selector for scheduling server pod |
| operator | object | `{"leaderElection":{"enabled":true,"namespace":""},"resizePolicy":[],"resources":{"limits":{"memory":"128Mi"},"requests":{"cpu":"10m","memory":"128Mi"}}}` | All settings related to the "operator" kubernetes container |
| operator.leaderElection.enabled | bool | `true` | enables leader election for the operator (required when running multiple replicas) |
| operator.leaderElection.namespace | string | `""` | namespace where the leader election lease resource will be created (defaults to release namespace) |
| operator.resizePolicy | list | `[]` | resize policy for the operator container (requires Kubernetes 1.27+ with InPlacePodVerticalScaling feature gate) |
| operator.resources | object | `{"limits":{"memory":"128Mi"},"requests":{"cpu":"10m","memory":"128Mi"}}` | resource limits and requests |
| operatorMetricsAddress | string | `":8080"` | Address to expose operator metrics |
| podAnnotations | object | `{}` | additional annotations for pod |
| podLabels | object | `{}` | additional labels for pod |
| podSecurityContext | object | `{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}}` | security context for pod |
| prometheusBasicAuthUsername | string | `""` | HTTP basic auth username for querying Prometheus |
| prometheusBearerTokenPath | string | `""` | Path to a bearer token file for querying Prometheus. Mount the file via extraApiVolumes/extraApiVolumeMounts. For the basic auth password, use extraApiArgs, since Pyrra only accepts it as a plain flag value. |
| prometheusExternalUrl | string | `""` | URL to public-facing prometheus UI in case it differs from prometheusUrl |
| prometheusRule.enabled | bool | `false` | enables creation of PrometheusRules to monitor Pyrra |
| prometheusRule.labels | object | `{}` | Set labels that will be applied on all PrometheusRules (alerts) |
| prometheusRule.pyrraReconciliationError.severity | string | `"warning"` | Set severity for PyrraReconciliationError alert |
| prometheusUrl | string | `"http://prometheus-operated.monitoring.svc.cluster.local:9090"` | URL to prometheus instance with metrics |
| resizePolicy | list | `[]` | resize policy for the server container (requires Kubernetes 1.27+ with InPlacePodVerticalScaling feature gate) |
| resources | object | `{"limits":{"memory":"128Mi"},"requests":{"cpu":"10m","memory":"128Mi"}}` | resource limits and requests for server pod |
| route | object | `{"main":{"additionalRules":[],"annotations":{},"apiVersion":"gateway.networking.k8s.io/v1","enabled":false,"filters":[],"hostnames":[],"httpsRedirect":false,"kind":"HTTPRoute","labels":{},"matches":[{"path":{"type":"PathPrefix","value":"/"}}],"parentRefs":[],"timeouts":{}}}` | Gateway API HTTPRoute configuration. Supports multiple named routes. |
| route.main.additionalRules | list | `[]` | additional custom rules prepended to the route rules |
| route.main.annotations | object | `{}` | additional annotations for the route |
| route.main.apiVersion | string | `"gateway.networking.k8s.io/v1"` | Gateway API version |
| route.main.enabled | bool | `false` | enables HTTPRoute for server UI |
| route.main.filters | list | `[]` | request/response filter configuration |
| route.main.hostnames | list | `[]` | hostnames to match for this route |
| route.main.httpsRedirect | bool | `false` | redirect all traffic to HTTPS (301) |
| route.main.kind | string | `"HTTPRoute"` | Route kind (HTTPRoute or GRPCRoute) |
| route.main.labels | object | `{}` | additional labels for the route |
| route.main.matches | list | `[{"path":{"type":"PathPrefix","value":"/"}}]` | path/header match conditions |
| route.main.parentRefs | list | `[]` | parentRefs defines which Gateways this route attaches to |
| route.main.timeouts | object | `{}` | timeout configuration |
| routePrefix | string | `""` | URL under which the pyrra web server is serving content. this can be set when running behind a reverse proxy. Must start with a slash and not end with a slash. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | security context for each container |
| service.annotations | object | `{}` | Annotations to add to the service |
| service.ipFamilies | list | `[]` | Ordered list of IP families assigned to the service. Supported values: IPv4, IPv6. When using dual-stack, the first entry becomes the primary IP family. Leave empty to use the Kubernetes cluster default. |
| service.ipFamilyPolicy | string | `""` | IP family policy for the service. Supported values: SingleStack, PreferDualStack, RequireDualStack. Leave empty to use the Kubernetes cluster default. |
| service.nodePort | string | `""` | service nodePort to expose node port for HTTP, choose port between <30000-32767> |
| service.operatorMetricsPort | int | `8080` | service port for operator metrics |
| service.port | int | `9099` | service port for server |
| service.type | string | `"ClusterIP"` | service type for server |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automountServiceAccountToken | bool | `false` | Whether pods running as this service account automatically mount the service account token, disabled by default; the pod mounts the token explicitly via `automountServiceAccountToken`. |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | The name of the service account to use, if not set and create is true, a name is generated using the fullname template |
| serviceMonitor.enabled | bool | `false` | enables servicemonitor for server monitoring |
| serviceMonitor.interval | string | `""` | Set interval for scraping metrics |
| serviceMonitor.jobLabel | string | `""` | provides the possibility to override the jobName if needed |
| serviceMonitor.labels | object | `{}` | Set labels for the ServiceMonitor, use this to define your scrape label for Prometheus Operator |
| serviceMonitor.metricRelabelings | list | `[]` | Set metric relabelings for the ServiceMonitor |
| serviceMonitor.relabelings | list | `[]` | Set relabelings for the ServiceMonitor |
| serviceMonitorOperator.enabled | bool | `false` | enables servicemonitor for operator monitoring |
| serviceMonitorOperator.interval | string | `""` | Set interval for scraping metrics |
| serviceMonitorOperator.jobLabel | string | `""` | provides the possibility to override the jobName if needed |
| serviceMonitorOperator.labels | object | `{}` | Set labels for the ServiceMonitor, use this to define your scrape label for Prometheus Operator |
| serviceMonitorOperator.metricRelabelings | list | `[]` | Set metric relabelings for the ServiceMonitor |
| serviceMonitorOperator.relabelings | list | `[]` | Set relabelings for the ServiceMonitor |
| tolerations | object | `{}` | tolerations for scheduling server pod |
| validatingWebhookConfiguration.enabled | bool | `false` | enables admission webhook for server to validate SLOs, this requires cert-manager to be installed |
| validatingWebhookConfiguration.failurePolicy | string | `"Fail"` | 'Fail' or 'Ignore' are valid values |

## Upgrading

A major chart version change indicates that there is an incompatible breaking change needing manual actions.
