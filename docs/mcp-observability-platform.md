# mcp-observability-platform

[mcp-observability-platform](https://github.com/giantswarm/mcp-observability-platform) is the MCP server for the Observability Platform.
A user signs in to it through Dex.
The server sends each caller's Dex `id_token` to `grafana-mcp`, a second Grafana instance that verifies the token and applies the caller's org roles.

The shared collection installs the server on every management cluster, in every stage, `stable` included:

- `bases/collections/shared/base/mcp-observability-platform.yaml` holds the OCIRepository and the HelmRelease.
- The release runs in the namespace `mcp-observability-platform`.
- The values come from `default/apps/mcp-observability-platform` in shared-configs, through the `collection-konfiguration` Konfiguration.
- The server keeps its OAuth tokens, client registrations and sign-ins in progress in memory. A restart signs every caller out, and MCP clients register again.

## Chart version

The OCIRepository selects chart `>=0.7.0`.
The values in shared-configs set Grafana auth mode `jwt`.
v0.5.0 and v0.6.0 have no jwt mode.
0.7.0 is the expected first release with it.
Confirm the bound against the actual first jwt release before the stage change merges.

The testing stage selects the newest release or release candidate, through the `ocirepo-semver-rc-or-stable` component of each provider's testing stage.
The lower bound does not apply there.

## What each installation provides

Each installation provides these objects before the stage change reaches it.

In the installation's config repository:

- The Dex static client `mcp-observability-platform` in `oidc.extraStaticClients` of `installations/<installation>/apps/dex-app/configmap-values.yaml.patch`.
  It reads its secret with `secretRef: {name: dex-client-mcp-observability-platform, key: secret}`.
  It lists no trusted peers, so no other Dex client mints tokens with its audience.

In the installation's directory of its management-clusters repository, under `extras/`:

- The Namespace `mcp-observability-platform`. The Secret below needs it before the HelmRelease creates it.
- The SOPS-encrypted Secret `mcp-observability-platform-oauth-credentials` in `mcp-observability-platform`, with the keys:
  - `clientSecret`: the Dex client secret. The chart reads it from `oauth.dex.existingSecret`.
  - `encryptionKey`: the OAuth encryption key. The chart reads it from `oauth.encryption.existingSecret`.
- The SOPS-encrypted Secret `dex-client-mcp-observability-platform` in `giantswarm`, with the key `secret`: the same value as `clientSecret`.

### Without the Secret

The Deployment reads `clientSecret` with a `secretKeyRef` that is not optional.
Without the Secret, Helm creates every object and the pod stays in `CreateContainerConfigError`.
The HelmRelease waits for the pod, fails the install after its 10-minute timeout and retries it 10 times.
It then stays not Ready.
Other releases on the installation are not affected.
This behaviour follows from the chart template and the HelmRelease settings. It is not tested on a cluster.

## graveler cutover

graveler runs the server as a hand-installed Helm release `mcp-observability-platform` in the namespace `mcp-observability-platform`, with no Flux object.
The new HelmRelease uses the same release name and namespace.
graveler moves to this HelmRelease in this order:

1. Release observability-operator with the JWT org mapping on, grafana-app with `grafanaMcp`, and the first jwt release of mcp-observability-platform.
2. Delete the hand-applied `grafana-mcp` objects in `monitoring`. Then merge the shared-configs change that enables `grafanaMcp` (fleet switch 1). Helm does not adopt objects it did not create.
3. Run the lockstep Grafana upgrade check on graveler.
4. Merge the graveler Secrets in https://github.com/giantswarm/giantswarm-management-clusters/pull/3018
   This rotates the Dex client secret. MCP sign-ins on graveler fail and running sessions end until step 6 installs the new release.
5. Delete the hand-installed release and its leftover Secret:
   - `helm uninstall mcp-observability-platform -n mcp-observability-platform`
   - `kubectl -n mcp-observability-platform delete secret mcp-observability-platform-valkey-auth`
6. Merge the stage change (fleet switch 2). Flux installs the server on graveler and on every other installation.

## Rollback

Revert the stage change, then the shared-configs change.
Flux uninstalls the server and `grafana-mcp`.
The main Grafana stays untouched.
