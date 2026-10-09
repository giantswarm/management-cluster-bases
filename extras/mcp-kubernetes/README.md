# MCP Kubernetes

## Description

MCP Kubernetes server provides a Kubernetes API endpoint for MCP (Model Context Protocol) integration.
It includes a Valkey instance for OAuth session persistence.

## Usage

Reference this extra in your cluster's extras:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-kubernetes?ref=main
  - oauth-credentials.enc.yaml
  - valkey-credentials.enc.yaml
```

## Configuration

- **Templates**: `shared-configs/default/apps/mcp-kubernetes/`
- **Secrets**: Inline Kubernetes Secrets in `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-kubernetes/`

## Version Strategy

The `OCIRepository` is capped at the newest stable the fleet runs
(`semver: "<=X.Y.Z"`), so a new stable release never rolls onto every
installation at once:

1. **Test installations first.** Their `extras/kustomization.yaml` (in the
   installation's management-clusters repository, next to the `./mcp-*/`
   entries) lifts the cap and follows every newer stable release:

   ```yaml
   patches:
     - patch: |-
         - op: replace
           path: /spec/ref/semver
           value: ">=1.11.2"
       target:
         kind: OCIRepository
         name: mcp-kubernetes
   ```

2. **Then the fleet.** Once a release ran on the test installations, a pull
   request here raises the cap in `oci-repository.yaml` to it.

The same strategy holds for `mcp-capi` and `mcp-prometheus`.

## Prerequisites

For the Konfiguration to work, the `flux-extras` Kustomization must pass the `cluster_name` variable.

Add this target to the `replacements` section in `<customer>-management-clusters/management-clusters/<cluster>/kustomization.yaml`:

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

## Deploying to a Cluster

### 1. Create the cluster extras directory

```bash
mkdir -p <customer>-management-clusters/management-clusters/<mc>/extras/mcp-kubernetes
```

### 2. Create the kustomization

Create `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-kubernetes/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-kubernetes?ref=main
  - oauth-credentials.enc.yaml
  - valkey-credentials.enc.yaml
```

### 3. Create the OAuth credentials secret

Create `oauth-credentials.enc.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mcp-kubernetes-oauth-credentials
  namespace: mcp-kubernetes
type: Opaque
stringData:
  dex-client-secret: "your-dex-client-secret"
  oauth-encryption-key: "your-32-byte-encryption-key"
```

Encrypt with SOPS:

```bash
export SOPS_AGE_KEY="op://Dev Common/<mc>.agekey/notesPlain"
op run -- sops -e -i oauth-credentials.enc.yaml
```

### 4. Create the Valkey credentials secret

Create `valkey-credentials.enc.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mcp-kubernetes-valkey-auth
  namespace: mcp-kubernetes
type: Opaque
stringData:
  default: "your-valkey-password"
```

Encrypt with SOPS.

### 5. Add to the extras kustomization

Add to `<customer>-management-clusters/management-clusters/<mc>/extras/kustomization.yaml`:

```yaml
resources:
  # ... existing extras ...
  - ./mcp-kubernetes/
```

## Troubleshooting

### OCIRepository Not Ready

```bash
kubectl get ocirepository mcp-kubernetes -n flux-giantswarm
kubectl describe ocirepository mcp-kubernetes -n flux-giantswarm
```

### Konfiguration Not Creating ConfigMap

```bash
kubectl get konfiguration mcp-kubernetes-konfiguration -n flux-giantswarm
kubectl logs -n flux-giantswarm deployment/konfiguration-controller
```

### HelmRelease Issues

```bash
kubectl get helmrelease mcp-kubernetes -n flux-giantswarm
kubectl describe helmrelease mcp-kubernetes -n flux-giantswarm
```

### Valkey Connection Issues

```bash
kubectl get pods -n mcp-kubernetes
kubectl logs -n mcp-kubernetes -l app.kubernetes.io/name=valkey
```
