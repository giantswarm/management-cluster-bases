# MCP Observability Platform

## Description

MCP Observability Platform exposes the installation's Grafana, Mimir, Loki,
Tempo and Alertmanager to MCP clients, scoped to the caller's Grafana
organizations. Source:
[`giantswarm/mcp-observability-platform`](https://github.com/giantswarm/mcp-observability-platform).
It includes a Valkey instance for the OAuth token store.

## Usage

Reference this extra in your cluster's extras:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/mcp-observability-platform?ref=main
  - oauth-credentials.enc.yaml
  - valkey-credentials.enc.yaml
  - dex-client-mcp-observability-platform-secret.yaml
```

## Configuration

- **Templates**: `shared-configs/default/apps/mcp-observability-platform/`
- **Grafana**: `grafana.authMode: jwt` against the installation's
  `grafana-mcp` instance (`monitoring` namespace), which validates the
  caller's Dex ID token (`aud: mcp-observability-platform`).
- **Dex client**: id `mcp-observability-platform`, an `oidc.extraStaticClients`
  entry in `<customer>-configs/installations/<mc>/apps/dex-app/configmap-values.yaml.patch`
  with `secretRef: {name: dex-client-mcp-observability-platform, key: secret}`.
- **Secrets**: SOPS-encrypted Kubernetes Secrets in
  `<customer>-management-clusters/management-clusters/<mc>/extras/mcp-observability-platform/`:
  - `mcp-observability-platform-oauth-credentials` (namespace
    `mcp-observability-platform`): `clientSecret` (the Dex client secret) and
    `encryptionKey` (`openssl rand -hex 32`).
  - `mcp-observability-platform-valkey-auth` (namespace
    `mcp-observability-platform`): `password`, read by the server and by Valkey.
  - `dex-client-mcp-observability-platform` (namespace `giantswarm`): `secret`,
    the same value as `clientSecret`.

## Version Strategy

Capped at the newest stable the fleet runs; test installations follow newer
stable releases first. See [mcp-kubernetes](../mcp-kubernetes/README.md#version-strategy).

## Prerequisites

For the Konfiguration to work, the `flux-extras` Kustomization must pass the
`cluster_name` variable. See [mcp-kubernetes](../mcp-kubernetes/README.md#prerequisites).
