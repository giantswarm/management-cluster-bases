# MCP CAPI

## Description

[mcp-capi](https://github.com/giantswarm/mcp-capi) is the Model Context Protocol
server for Cluster API: it lets agents list and inspect clusters, machines and
machine deployments on the management cluster.

Agents get **read-only** access: the chart runs with `readOnly: true`, so only
the tools that read (list, get, status, health, backup, provider lookups) are
registered and every mutating Kubernetes call is refused. The clusters on a
management cluster are rendered by the cluster charts from Apps and
HelmReleases in Git; `gitopsGuard: true` refuses writes to such objects should
writes ever be enabled, because the controller would revert them.

Workload cluster **credentials never leave the management cluster** through an
agent: `exposeKubeconfig: false` (the default since mcp-capi 0.4.0) keeps
`capi_get_kubeconfig` unregistered and makes `capi_backup_cluster` refuse
`include_secrets`, read-only or not. This is an absolute rule on Giant Swarm
management clusters; do not set it to true in a cluster's `user-values`. All
three switches are stated in the `shared-configs` template.

It runs as an OAuth 2.1 resource server (`mcp-oauth`) and **acts as the
person**: muster forwards the caller's Dex ID token, mcp-capi validates it and
presents the very same token to the Kubernetes API server. The pod mounts no
ServiceAccount token and the chart renders no RBAC — the person's RBAC governs
every CAPI operation. A Valkey instance persists OAuth sessions.

## Usage

Reference this extra in your cluster's extras:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-capi?ref=main
  - oauth-credentials.enc.yaml
  - valkey-credentials.enc.yaml
```

## Configuration

- **Templates**: `shared-configs/default/apps/mcp-capi/`
- **Secrets**: Inline Kubernetes Secrets in `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-capi/`
- **muster**: add a `group: capi` entry to the `agent-platform-mcps.mcpServers`
  list of the muster that should reach it (`auth.mode: forward` on the same
  cluster, `exchange` from another management cluster), in
  `<customer>-configs/installations/<mc>/apps/agent-platform/configmap-values.yaml.patch`.

## Version Strategy

Auto-updates enabled via SemVer range `>=0.0.0`. New versions deploy automatically when pushed to the OCI registry.

## Prerequisites

Same as [mcp-kubernetes](../mcp-kubernetes/README.md): the `flux-extras`
Kustomization must pass the `cluster_name` variable.

## Deploying to a Cluster

### 1. Create the cluster extras directory

```bash
mkdir -p <customer>-management-clusters/management-clusters/<mc>/extras/mcp-capi
```

### 2. Create the kustomization

Create `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-capi/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-capi?ref=main
  - oauth-credentials.enc.yaml
  - valkey-credentials.enc.yaml
```

### 3. Create the OAuth credentials secret

Create `oauth-credentials.enc.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mcp-capi-oauth-credentials
  namespace: mcp-capi
type: Opaque
stringData:
  dex-client-secret: "<random secret; the Dex client is registered as mcpCapi in dex-app>"
  oauth-encryption-key: "<openssl rand -base64 32>"
```

Encrypt with SOPS (`.sops.yaml` in the repo selects the cluster's age key by path):

```bash
sops -e -i oauth-credentials.enc.yaml
```

### 4. Create the Valkey credentials secret

Create `valkey-credentials.enc.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mcp-capi-valkey-auth
  namespace: mcp-capi
type: Opaque
stringData:
  default: "<openssl rand -base64 32>"
```

and encrypt it the same way.

### 5. Private management clusters

When Dex is only reachable on a private address with a private CA (the
mcp-kubernetes extra has a `dex-ca-secret.enc.yaml` there), add the same for
mcp-capi (`mcp-capi-dex-ca` in namespace `mcp-capi`) and a `user-values.yaml`
ConfigMap patched into the HelmRelease with:

```yaml
oauth:
  allowPrivateURLs: true
  dex:
    caSecret:
      name: mcp-capi-dex-ca
```

The central muster reaches the server through a tunnelport `RemoteApp`
(`mcp-capi-<mc>`), like mcp-kubernetes and mcp-prometheus.
