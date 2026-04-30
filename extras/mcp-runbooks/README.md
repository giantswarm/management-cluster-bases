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
```

No per-cluster secrets are required.

## Version Strategy

Auto-updates enabled via SemVer range `>=0.0.0`. New versions deploy
automatically when pushed to the OCI registry.

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
```

### 3. Add to the extras kustomization

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
