# PRO (Portfolio Roadmap Organizer)

## Description

PRO is an MCP server that exposes Giant Swarm's GitHub Projects V2 boards
(roadmap and customer boards) to AI assistants over the Model Context Protocol
(streamable HTTP transport). It runs bearer-only: every request carries a GitHub
token the caller obtained itself, PRO verifies it against the GitHub API and
uses it for that request, so board changes are attributed to the person. PRO
owns no GitHub OAuth App and runs no authorization server; muster holds the
person's GitHub grant (obtained with the Dex GitHub App's client) and pins
GitHub as the authorization server on the pro MCPServer.

## Usage

Reference this extra in your cluster's extras:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/pro?ref=main
```

## Configuration

- **Templates**: `shared-configs/default/apps/pro/` (`OAUTH_BEARER_ONLY=true`,
  `OAUTH_ISSUER_URL` = the public URL, which is the RFC 9728 resource
  identifier)
- **Secrets**: none. PRO holds no credentials of its own.
- **muster side**: an `MCPServer` for PRO with `spec.auth.authorizationServer`
  pinned to `https://github.com/login/oauth` (authorize/token endpoints,
  `clientCredentialsSecretRef` naming the Dex GitHub App's client Secret,
  `grantScope: subject`). See
  `<customer>-management-clusters/management-clusters/<mc>/extras/agent-platform/mcpservers/`
  on gazelle for the reference manifest.

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

### GitHub authorization

PRO accepts GitHub user tokens; it registers nothing at GitHub itself. The
GitHub App whose client muster uses (the Dex GitHub App of the installation)
must list muster's callback URL
`https://muster.<codename>.<base>/oauth/proxy/callback`, carry the
Organization → Projects read & write permission (plus the repository
permissions the other GitHub-backed servers need) and be installed on the
organization that owns the boards.

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
```

### 3. Add to the extras kustomization

In `<customer>-management-clusters/management-clusters/<mc>/extras/kustomization.yaml`:

```yaml
resources:
  # ... existing extras ...
  - ./pro/
```

### 4. Register PRO with muster

Add an `MCPServer` for `http://pro.mcp-pro.svc.cluster.local:8080/mcp`
(`toolPrefix: pro`, `auth.type: oauth`) with the authorization server pinned to
GitHub as described under Configuration.

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

A healthy bearer-only start logs `Bearer-only auth enabled`. `OAuth 2.1
enabled` means `GITHUB_OAUTH_CLIENT_ID`/`GITHUB_OAUTH_CLIENT_SECRET` are still
set: they take precedence over `OAUTH_BEARER_ONLY`.
