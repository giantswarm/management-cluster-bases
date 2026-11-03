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

Test installations follow newer stable releases first. See
[mcp-kubernetes](../mcp-kubernetes/README.md#version-strategy).

The cap is `<=0.5.0`, the first release with Grafana jwt auth. A release
below 0.5.0 accepts `grafana.authMode: jwt` but still reads the Grafana
service account token Secret, so its pod fails with
`CreateContainerConfigError`. List this extra on an installation only when
both hold:

- the installation resolves 0.5.0 or later: a test-stage patch `>=0.5.0`,
  or the release 0.5.0 is out;
- the installation runs `grafana-mcp` in `monitoring`.

`grafana-mcp` comes from these pull requests, merged in this order:

1. https://github.com/giantswarm/grafana-app/pull/578 (chart 2.43.0 or later)
2. https://github.com/giantswarm/shared-configs/pull/797
3. https://github.com/giantswarm/management-cluster-bases/pull/907 (the
   `grafana-mcp` HelmRelease on the testing, staging and stable-testing
   stages, Giant Swarm installations only)

## Installations

| Installation | State |
|---|---|
| graveler | Test stage. Cutover from a hand-applied release, below. |
| gazelle | Follow-up: after the release 0.5.0 and after pull request 907 reaches the staging stage. |

## Graveler cutover

Graveler runs a hand-applied release today:

- the Helm release `mcp-observability-platform` in `monitoring`, installed by
  the suspended HelmRelease `org-giantswarm/graveler-mcp-observability-platform`;
- the OCIRepository and the values ConfigMap
  `graveler-mcp-observability-platform-values` in `org-giantswarm`;
- the Secrets `mcp-observability-platform-oauth` and
  `mcp-observability-platform-grafana` in `monitoring`;
- the hand-applied `grafana-mcp` Deployment and Service, the NetworkPolicy
  `grafana-mcp-renderer-ingress` and the CiliumNetworkPolicy
  `grafana-mcp-renderer-egress`, all in `monitoring`.

Order:

1. Release mcp-observability-platform 0.5.0.
2. Merge this extra and its shared-configs template. Nothing deploys them yet.
3. Uninstall the hand-applied release:
   `helm uninstall mcp-observability-platform -n monitoring`.
   The new release collides with it on the ClusterRole and the
   ClusterRoleBinding `mcp-observability-platform` and on the HTTPRoute
   hostname. A suspended HelmRelease does not uninstall its release on
   deletion, so this step runs first.
4. Delete the hand-applied objects in `org-giantswarm`:
   `kubectl -n org-giantswarm delete helmrelease,ocirepository graveler-mcp-observability-platform`
   and `kubectl -n org-giantswarm delete configmap graveler-mcp-observability-platform-values`.
5. Delete the stray Secrets:
   `kubectl -n monitoring delete secret mcp-observability-platform-oauth mcp-observability-platform-grafana`.
6. Merge the graveler change in giantswarm-management-clusters. Flux applies
   the extra, the Valkey and the new Dex client Secret.
7. Keep the hand-applied `grafana-mcp` objects until pull request 907 runs
   `grafana-mcp` on graveler. Then delete them.

Outage window: the graveler change rotates the Dex client secret, and
dex-app restarts with the new value. From that merge until the new release
installs, every sign-in to the MCP fails. Running sessions end too: the
hand-applied release stored them in memory.

## Prerequisites

For the Konfiguration to work, the `flux-extras` Kustomization must pass the
`cluster_name` variable. See [mcp-kubernetes](../mcp-kubernetes/README.md#prerequisites).
