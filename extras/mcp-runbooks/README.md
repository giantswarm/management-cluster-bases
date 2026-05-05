# MCP Runbooks

## Description

MCP Runbooks server provides Giant Swarm operational runbooks over the Model
Context Protocol (streamable HTTP transport). Runbooks are embedded in the
container image at build time.

## Usage

Reference this extra in your cluster's extras:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-runbooks?ref=main
  - pull-secret.enc.yaml
```

## Configuration

- **Templates**: `shared-configs/default/apps/mcp-runbooks/`
- **Secrets**: Inline Kubernetes Secrets in `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-runbooks/`

## Version Strategy

Auto-updates enabled via SemVer range `>=0.0.0`. New versions deploy
automatically when pushed to the OCI registry.

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
mkdir -p <customer>-management-clusters/management-clusters/<mc>/extras/mcp-runbooks
```

### 2. Create the kustomization

Create `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-runbooks/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-runbooks?ref=main
  - pull-secret.enc.yaml
```

### 3. Create the image pull secret

Create `pull-secret.enc.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mcp-runbooks-pull-secret
  namespace: mcp-runbooks
type: kubernetes.io/dockerconfigjson
stringData:
  .dockerconfigjson: "your-dockerconfigjson"
```

Encrypt with SOPS:

```bash
export SOPS_AGE_KEY="op://Dev Common/<mc>.agekey/notesPlain"
op run -- sops -e -i pull-secret.enc.yaml
```

### 4. Add to the extras kustomization

Add to `<customer>-management-clusters/management-clusters/<mc>/extras/kustomization.yaml`:

```yaml
resources:
  # ... existing extras ...
  - ./mcp-runbooks/
```

## Troubleshooting

### OCIRepository Not Ready

```bash
kubectl get ocirepository mcp-runbooks -n flux-giantswarm
kubectl describe ocirepository mcp-runbooks -n flux-giantswarm
```

### Konfiguration Not Creating ConfigMap

```bash
kubectl get konfiguration mcp-runbooks-konfiguration -n flux-giantswarm
kubectl logs -n flux-giantswarm deployment/konfiguration-controller
```

### HelmRelease Issues

```bash
kubectl get helmrelease mcp-runbooks -n flux-giantswarm
kubectl describe helmrelease mcp-runbooks -n flux-giantswarm
```

### Pod Issues

```bash
kubectl get pods -n mcp-runbooks
kubectl logs -n mcp-runbooks -l app.kubernetes.io/name=mcp-runbooks
```
