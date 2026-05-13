# PRO (Portfolio Roadmap Organizer)

## Description

PRO is an MCP server that exposes Giant Swarm's GitHub Projects V2 boards
(roadmap and customer boards) to AI assistants over the Model Context Protocol
(streamable HTTP transport). End users authenticate against GitHub via OAuth
2.1; PRO acts as the OAuth issuer for the MCP token.

## Usage

Reference this extra in your cluster's extras:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/pro?ref=main
  - oauth-credentials.enc.yaml
```

## Configuration

- **Templates**: `shared-configs/default/apps/pro/`
- **Secrets**: SOPS-encrypted Kubernetes Secret `pro-oauth` (keys `client-id`,
  `client-secret`) in `<customer>-management-clusters/management-clusters/<mc>/extras/pro/`

## Version Strategy

Auto-updates enabled via SemVer range `>=0.0.0`. New chart versions deploy
automatically when pushed to the public OCI registry.

## Prerequisites

### `cluster_name` substitution

For the Konfiguration to work, the `flux-extras` Kustomization must pass the
`cluster_name` variable. Add this to the `replacements` section in
`<customer>-management-clusters/management-clusters/<cluster>/kustomization.yaml`:

```yaml
replacements:
  - source:
      kind: ConfigMap
      name: management-cluster-metadata
      namespace: flux-giantswarm
      fieldPath: data.NAME
    targets:
      - select:
          kind: Kustomization
          name: flux-extras
          namespace: flux-giantswarm
        fieldPaths:
          - spec.postBuild.substitute.cluster_name
        options:
          create: true
```

### GitHub OAuth App

A GitHub OAuth App must be registered with this Authorization callback URL:

```
https://pro.<codename>.<base>/github/callback
```

The resulting Client ID and Client Secret are stored in the `pro-oauth` Secret.

## Deploying to a Cluster

### 1. Create the cluster extras directory

```bash
mkdir -p <customer>-management-clusters/management-clusters/<mc>/extras/pro
```

### 2. Create the kustomization

`<customer>-management-clusters/management-clusters/<mc>/extras/pro/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/pro?ref=main
  - oauth-credentials.enc.yaml
```

### 3. Create the OAuth credentials secret

Create `oauth-credentials.yaml` (plaintext, do **not** commit):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pro-oauth
  namespace: mcp-pro
type: Opaque
stringData:
  client-id: "<github-oauth-app-client-id>"
  client-secret: "<github-oauth-app-client-secret>"
```

Encrypt with SOPS:

```bash
export SOPS_AGE_KEY="op://Dev Common/<mc>.agekey/notesPlain"
op run -- sops -e oauth-credentials.yaml > oauth-credentials.enc.yaml
rm oauth-credentials.yaml
```

### 4. Add to the extras kustomization

In `<customer>-management-clusters/management-clusters/<mc>/extras/kustomization.yaml`:

```yaml
resources:
  # ... existing extras ...
  - ./pro/
```

## Troubleshooting

### OCIRepository Not Ready

```bash
kubectl get ocirepository pro -n flux-giantswarm
kubectl describe ocirepository pro -n flux-giantswarm
```

### Konfiguration Not Creating ConfigMap

```bash
kubectl get konfiguration pro-konfiguration -n flux-giantswarm
kubectl logs -n flux-giantswarm deployment/konfiguration-controller
```

### HelmRelease Issues

```bash
kubectl get helmrelease pro -n flux-giantswarm
kubectl describe helmrelease pro -n flux-giantswarm
```

### Pod Issues

```bash
kubectl get pods -n mcp-pro
kubectl logs -n mcp-pro -l app.kubernetes.io/name=pro
```
