# MCP PagerDuty

## Description

MCP PagerDuty server exposes PagerDuty's official MCP server (HTTP transport,
read-only by default) for in-cluster consumption by muster. Source:
[`giantswarm/pagerduty-mcp-server`](https://github.com/giantswarm/pagerduty-mcp-server),
a fork of [`PagerDuty/pagerduty-mcp-server`](https://github.com/PagerDuty/pagerduty-mcp-server)
with HTTP transport added.

## Usage

Reference this extra in your cluster's extras:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-pagerduty?ref=main
  - api-token.enc.yaml
```

## Configuration

- **Templates**: `shared-configs/default/apps/mcp-pagerduty/`
- **Source**: image and chart are published to the public `gsoci.azurecr.io`
  registry (the fork [`giantswarm/pagerduty-mcp-server`](https://github.com/giantswarm/pagerduty-mcp-server)
  is public), so no image or OCI pull secrets are required.
- **Secrets**: Inline Kubernetes Secret in `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-pagerduty/`:
  - `pagerduty-mcp` (key `apiKey`) — PagerDuty **User API Token**. Account-level
    REST API keys break `/users/me` and degrade user-scoped tool results.

## Version Strategy

Auto-updates enabled via SemVer range `>=0.0.0`. New chart versions deploy
automatically when pushed to the OCI registry by CircleCI.

## Prerequisites

For the Konfiguration to work, the `flux-extras` Kustomization must pass the
`cluster_name` variable. Add this target to the `replacements` section in
`<customer>-management-clusters/management-clusters/<cluster>/kustomization.yaml`:

```yaml
replacements:
  - source:
      kind: ConfigMap
      name: management-cluster-metadata
      namespace: flux-giantswarm
      fieldPath: data.NAME
    targets:
      # ... existing targets ...
      - select:
          kind: Kustomization
          name: flux-extras
          namespace: flux-giantswarm
        fieldPaths:
          - spec.postBuild.substitute.cluster_name
        options:
          create: true
```

The muster CNP must also be configured to allow egress to the `mcp-pagerduty`
namespace on TCP/8080. Once `giantswarm/muster` exposes the
`networkPolicy.cilium.additionalEgress` knob (PR
[#TBD](https://github.com/giantswarm/muster/pulls)), add:

```yaml
networkPolicy:
  cilium:
    additionalEgress:
      - toEndpoints:
          - matchLabels:
              k8s:io.kubernetes.pod.namespace: mcp-pagerduty
              app.kubernetes.io/name: mcp-pagerduty
        toPorts:
          - ports:
              - port: "8080"
                protocol: TCP
```

## Deploying to a Cluster

### 1. Create the cluster extras directory

```bash
mkdir -p <customer>-management-clusters/management-clusters/<mc>/extras/mcp-pagerduty
```

### 2. Create the kustomization

Create `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-pagerduty/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-pagerduty?ref=main
  - api-token.enc.yaml
```

### 3. Create the PagerDuty API token secret

`api-token.enc.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pagerduty-mcp
  namespace: mcp-pagerduty
type: Opaque
stringData:
  apiKey: "your-pagerduty-user-api-token"
```

Use a **User API Token** (My Profile → User Settings → API Access on
`<subdomain>.eu.pagerduty.com` for EU accounts) rather than an account-level
REST API key. Encrypt with SOPS as above.

### 4. Add to the extras kustomization

Add to `<customer>-management-clusters/management-clusters/<mc>/extras/kustomization.yaml`:

```yaml
resources:
  # ... existing extras ...
  - ./mcp-pagerduty/
```

### 5. Register with muster

Add an MCPServer resource pointing at the in-cluster service. Example —
`<customer>-management-clusters/management-clusters/<mc>/extras/muster/mcpservers/<mc>-mcp-pagerduty.yaml`:

```yaml
apiVersion: muster.giantswarm.io/v1alpha1
kind: MCPServer
metadata:
  name: <mc>-mcp-pagerduty
  namespace: muster
  labels:
    muster.giantswarm.io/management-cluster: <mc>
    muster.giantswarm.io/type: mcp-pagerduty
spec:
  type: streamable-http
  url: http://mcp-pagerduty.mcp-pagerduty.svc.cluster.local:8080/mcp
  timeout: 30
  autoStart: true
  toolPrefix: pd
  description: Read-only PagerDuty MCP for incident troubleshooting
  auth:
    type: none
    forwardToken: false
```

## Troubleshooting

### OCIRepository Not Ready

```bash
kubectl get ocirepository mcp-pagerduty -n flux-giantswarm
kubectl describe ocirepository mcp-pagerduty -n flux-giantswarm
```

### Konfiguration Not Creating ConfigMap

```bash
kubectl get konfiguration mcp-pagerduty-konfiguration -n flux-giantswarm
kubectl logs -n flux-giantswarm deployment/konfiguration-controller
```

### HelmRelease Issues

```bash
kubectl get helmrelease mcp-pagerduty -n flux-giantswarm
kubectl describe helmrelease mcp-pagerduty -n flux-giantswarm
```

### Pod Issues

```bash
kubectl get pods -n mcp-pagerduty
kubectl logs -n mcp-pagerduty -l app.kubernetes.io/name=mcp-pagerduty
```

### MCPServer Disconnected

If the MCPServer status stays `Disconnected` or `Failed`, check muster's CNP
egress allowlist — it must include `mcp-pagerduty/*:8080`.
