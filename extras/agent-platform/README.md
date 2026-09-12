# Agent Platform Extras

This directory contains the Flux resources required to deploy the
`agent-platform` meta-package on a Giant Swarm management cluster.

## Overview

`agent-platform` (chart `>=2.5.5 <4.0.0`; the 4.x line -- the kagent API v2
migration, giantswarm/giantswarm#37705 -- is admitted per installation through an
overlay patch of the `OCIRepository`, see
[Cut-over to meta chart 4.x](#cut-over-to-meta-chart-4x-per-installation))
is a **meta-package (app-of-apps)**:
it no longer bundles sub-charts, but renders each component as its own Flux
`OCIRepository` + `HelmRelease` (version ranges resolved at reconcile time, so
component releases roll forward with no PR). Components include muster (MCP
aggregator / OAuth resource server), valkey (OAuth session storage),
agentgateway (MCP data plane), kagent (on 4.x the kagent API v2 line,
`kagent.dev/v1alpha3`, with Agent Substrate -- the gVisor worker pods the agents
run in -- as part of the component), klaus-gateway, agent-sandbox, the
managers (agent-manager, model-manager), the Dev Portal (backstage) and the
`agent-platform-connectivity` chart that owns the wiring (public `HTTPRoute`,
`Gateway`, `AgentgatewayParameters`, CiliumNetworkPolicies).

On Giant Swarm clusters the meta-package's `HelmRelease` sets:

```yaml
spec:
  values:
    gitops:
      namespace: flux-giantswarm      # render the child Flux CRs here — exempt
      targetNamespace: agent-platform  #   from flux-multi-tenancy; workloads here
    components:
      flux:
        enabled: false                 # the cluster runs its own Flux
```

The child `HelmRelease`s are created in `flux-giantswarm` (the
flux-multi-tenancy Kyverno policy rejects HelmReleases lacking
`serviceAccountName` outside `flux-giantswarm`/`giantswarm`/`monitoring`) and
install their workloads into `agent-platform`.

`components.flux.enabled: false` switches off the chart's bundled Flux engine
(a conditional `flux-engine` subchart carrying the Flux CRDs, the Flux Operator
and a `FluxInstance`; **on by default** so the chart installs on a cluster that
has no Flux). A management cluster runs its own Flux and installs this chart
*through* it, and helm-controller's default `install.crds: Create` would
force-apply the subchart's Flux CRDs over the cluster's own — so the value is
set here, in the fleet. The `HelmRelease` additionally sets `install.crds: Skip`
and `upgrade.crds: Skip`: helm-controller applies a chart's `crds/` *before* it
renders the templates, and the meta chart's `crds/` are exactly the engine's
Flux CRDs, so with `Skip` even a flipped value cannot touch the cluster's own
Flux CRDs (component CRDs are unaffected — they live in the child
`HelmRelease`s, each with its own `crds: CreateReplace`).

## Tenant identity of the agents

The agents' Flux `HelmRelease`s (written by the Dev Portal and by agent-manager
into the `kagent` namespace) execute as the ServiceAccount `kagent-flux`, bound
to `cluster-admin` by a namespace-scoped RoleBinding. The
`agent-platform-connectivity` chart renders both objects whenever the kagent
component is on (`kagent.fluxServiceAccountName`, one value that also drives
agent-manager and the portal), so this extra carries neither.

The `kagent` namespace itself is this extra's (`namespace.yaml`), on every
management cluster: the fleet stages kagent's Secrets there before turning
kagent on, and the chart only renders the namespace while kagent is on. When
kagent is on the chart adopts it (same spec).

## Prerequisites

CRDs are **app-owned**: each component ships its own CRDs in the chart's
`crds/` directory (on the kagent API v2 line as the `kagent-crds` and
`substrate-crds` components, templates with `helm.sh/resource-policy: keep`)
and the meta-package sets `crds: CreateReplace` on the component, so the CRDs
are installed and upgraded with the component itself. There is no separate CRD
bundle. CR-before-CRD ordering is handled inside the child releases:
`agent-platform-connectivity` and `agent-platform-mcps` `dependsOn` the
CRD-owning components, so a CR is never applied before its CRD exists. No
manual `helm install` for CRDs is required, and a cluster's
`crds/kustomization.yaml` carries no standalone reference to
`giantswarm/muster/v*/helm/muster/crds/*.yaml`.

The Gateway API v1 CRDs and a Gateway to attach muster's public `HTTPRoute` to
(e.g. `envoy-gateway-system/giantswarm-default`) remain cluster prerequisites.

## Configuration

Configuration is supplied via two ConfigMaps merged onto the HelmRelease:

1. **shared-configs** rendered into `agent-platform-konfiguration` by the
   bundled `Konfiguration` resource. Requires a matching `agent-platform`
   template in `giantswarm-config` that renders values under the umbrella's
   `muster:` subchart prefix (e.g. `muster.muster.oauth.server.baseUrl`).
2. **per-cluster overrides** via a `agent-platform-user-values` ConfigMap
   appended by the consumer kustomization (see usage below).

Required per-cluster fields (template-time fail-guards reject install
otherwise):

| Field | Notes |
|---|---|
| `muster.muster.oauth.server.baseUrl` | Public muster URL (HTTPS) |
| `muster.muster.oauth.server.dex.issuerUrl` | Dex issuer on this cluster |
| `muster.muster.oauth.server.dex.clientId` | OAuth client pre-registered in Dex |
| `muster.muster.oauth.server.existingSecret` | Secret with `dex-client-secret`, `registration-token`, `oauth-encryption-key`, `valkey-password` |
| `muster.muster.gatewayAPI.httpRoute.parentRefs` | Public Gateway to attach to (e.g. `envoy-gateway-system/giantswarm-default`) |
| `muster.muster.gatewayAPI.httpRoute.hostnames` | Public hostnames |
| `valkey.valkey.auth.usersExistingSecret` | Conventionally the same Secret as above (key `valkey-password`) |

## Secrets Required

Before deployment, ensure this Secret exists in the `agent-platform` namespace
(conventionally a single Secret referenced from both `muster.muster.oauth.server.existingSecret`
and `valkey.valkey.auth.usersExistingSecret`):

```bash
kubectl create secret generic agent-platform-secrets \
  --namespace agent-platform \
  --from-literal=dex-client-secret=<dex-client-secret> \
  --from-literal=registration-token=$(openssl rand -hex 32) \
  --from-literal=oauth-encryption-key=$(openssl rand -base64 32) \
  --from-literal=valkey-password=$(openssl rand -base64 32)
```

## Usage

To deploy on a management cluster, reference this directory from
`giantswarm-management-clusters`:

```yaml
# management-clusters/<mc>/extras/agent-platform/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/agent-platform?ref=main
  - agent-platform-secrets.enc.yaml
  - ./mcpservers
  - ./secrets
generatorOptions:
  disableNameSuffixHash: true
configMapGenerator:
  - name: agent-platform-user-values
    namespace: flux-giantswarm
    files:
      - values=user-values.yaml
patches:
  - patch: |-
      - op: add
        path: /spec/valuesFrom/-
        value:
          kind: ConfigMap
          name: agent-platform-user-values
          valuesKey: values
    target:
      kind: HelmRelease
      name: agent-platform
```

## Cut-over to meta chart 4.x, per installation

The 4.x line of the meta chart is the kagent API v2 migration
(giantswarm/giantswarm#37705): kagent `kagent.dev/v1alpha3`, agents as Agent
Substrate actors in gVisor worker pods, a fresh kagent database, the `Agent`
CRD removed. It is a hard cut per installation -- the v1alpha2 agents and their
conversations do not survive it -- so this base admits no 4.x release: its
`OCIRepository` stays at `>=2.5.5 <4.0.0` until the last installation has cut
over, and each installation lifts the bound itself, in the order below. The
chart's [`UPGRADE.md`](https://github.com/giantswarm/agent-platform/blob/main/UPGRADE.md)
("3.x → 4.0") is the authoritative reference for what each release changes;
this section is the fleet's procedure around it.

### Cut-over prerequisites

- **Kubernetes 1.35** with the feature gates `ClusterTrustBundle`,
  `ClusterTrustBundleProjection` and `PodCertificateRequest` on kube-apiserver,
  kube-controller-manager **and every kubelet** (Substrate issues its workload
  identities as `certificates.k8s.io/v1beta1` `PodCertificateRequest`s). Where
  the cluster chart does not yet turn them on by default, the management
  cluster's cluster-app values set them under
  `internal.advancedConfiguration.{controlPlane.apiServer,controlPlane.controllerManager,kubelet}.featureGates`
  -- each list replaces the chart's default list, so the defaults are repeated
  next to the three gates, on all three components. Enabling them rolls the
  control plane and every node: do it ahead of the cut-over. A 4.x render with
  kagent on refuses a cluster that does not serve the API, naming the gates.
- **The Substrate snapshot store**: on CAPA the bucket
  `giantswarm-<codename>-substrate` with an IRSA role for Substrate's `atelet`
  and `ate-api-server` ServiceAccounts, provisioned by the connectivity chart
  from the fleet template; the store's location is a required 4.x value
  (`kagent.harness.snapshotLocation`). Non-AWS installations need a store of
  their own before the flag below is set.

### Step 1 -- the flag, in the installation's `<customer>-configs` repository

Values only the 4.x chart understands (the Substrate snapshot store and
WorkerPool, the kagent controller's DSN Secret `kagent-pg-kagent-v2-app`, the
gRPC A2A target `grpc://agentgateway.agent-platform.svc.cluster.local:8080`,
`agentManager.migration.gitopsNamespaces: [flux-giantswarm]`) live in the fleet
template of shared-configs behind one Konfiguration variable, off by default:
the 3.x chart's schema rejects unknown top-level keys, so a 4.x key rendered
fleet-wide would fail every `HelmRelease` still on 3.x. The installation's
cut-over turns the variable on in `installations/<mc>/config.yaml.patch`:

```yaml
agentPlatform:
  kagentApiV2: true
```

Once merged, the rendered `agent-platform-konfiguration` ConfigMap carries the
4.x values, and the installation's meta `HelmRelease` -- still on 3.x -- refuses
one render on the unknown keys. Nothing is applied (`remediateLastFailure:
false` keeps the running release); step 2 resolves it.

### Step 2 -- the bound lift and the agents, in the installation's management-clusters repository

One pull request in `giantswarm-management-clusters` (or the customer's
management-clusters repository), touching
`management-clusters/<mc>/extras/agent-platform/`:

1. **Lift the bound.** A Kustomize patch on this base's `OCIRepository`, next
   to the `agent-platform-user-values` patch of the kustomization above:

   ```yaml
   patches:
     - patch: |-
         - op: replace
           path: /spec/ref/semver
           value: ">=4.0.0 <5.0.0"
       target:
         kind: OCIRepository
         name: agent-platform
   ```

   The patch touches `spec.ref.semver` only. The base's `HelmRelease` keeps
   `spec.timeout: 20m` -- see the bound below -- and no per-installation patch
   lowers it.

2. **Move the agent chart to 1.x.** In `agents/oci-repository.yaml` the range
   `>=0.2.1 <1.0.0` becomes `>=1.0.0 <2.0.0`. The Generic `agent` chart 1.x
   renders one `AgentTemplate` and one `RemoteMCPServer` per release (see
   [Creating agents](#creating-agents-tenant-self-service)).

3. **Rewrite every GitOps-owned agent `HelmRelease`** in that directory to
   chart 1.x values: the removed placement keys (`runtime`, `replicas`,
   `resources`, `nodeSelector`, `tolerations`) dropped, `muster.toolNames` →
   `muster.tools`, every git skill pinned to a commit, `agent.iconUrl` kept;
   the two `driftDetection.ignore` paths
   `/spec/declarative/deployment/podSecurityContext` and
   `/spec/declarative/deployment/securityContext` removed (they name v1alpha2
   fields), drift detection itself stays enabled. agent-manager's migrate Job
   emits exactly this rewrite as a diff per GitOps-owned release once the 4.x
   connectivity release has run it (it never writes those releases itself):
   `kubectl -n kagent get configmap agent-manager-migrate-report -o yaml`.
   Anything the report still names as pending after the first 4.x reconcile is
   applied to the same directory before the contract step.

On merge the first 4.x reconcile installs the component `HelmRelease`s in
dependency order (`substrate-crds`, `kagent-crds` → connectivity → `substrate` →
`kagent` → the managers), the storage-version hooks migrate the three kept kagent
CRDs to `v1alpha3` (recording the objects in the ConfigMap
`kagent-storage-version-migration`), the connectivity release derives the
`kagent_v2` database and its Secret, and the migrate Job rewrites the
portal-created agents.

### The meta `HelmRelease` timeout bound

helm-controller installs the meta release with `--wait`, which returns when
every component `HelmRelease` is Ready, and fails the reconcile on
`spec.timeout` (helm-controller's default: 5 minutes). With kagent on, the first
4.x reconcile takes about 5–6 minutes through the cluster's own Flux: ≈220 s of
`--wait` for the nine component HelmReleases, then Substrate and kagent
readiness (measured by the ATS own-Flux scenario of
giantswarm/agent-platform#380, `tests/ats/test_own_flux.py`, which sets
`spec.timeout: 12m`). The floor is therefore **12 m**; this base's
`helm-release.yaml` sets `20m`, and a per-installation patch never lowers it.
The uninstall through the same Flux takes about 30–105 s and removes the
component releases in reverse-dependency waves.

### Step 3 -- the contract

Once every `AgentTemplate` in `kagent` is Ready
(`kubectl -n kagent get agenttemplates.kagent.dev`) and no agent release is
left on chart 0.x, the migrate Job's contract phase deletes the leftover
`kagent.dev/v1alpha2 Agent` objects and the five retired CRDs. It runs as a
re-run of the Job -- a clone under a new name, because `kubectl create job
--from` accepts CronJob sources only. The report ConfigMap is a single slot:
save it before each run.

```sh
kubectl -n kagent get configmap agent-manager-migrate-report -o yaml > migrate-report-1.yaml
J=$(kubectl -n kagent get job -l app.kubernetes.io/component=agent-manager-migrate -o name | head -1)
kubectl -n kagent get "$J" -o json | jq 'del(.status, .metadata.uid, .metadata.resourceVersion,
    .metadata.creationTimestamp, .metadata.managedFields, .spec.selector,
    .spec.template.metadata.labels["batch.kubernetes.io/controller-uid"],
    .spec.template.metadata.labels["controller-uid"],
    .spec.template.metadata.labels["batch.kubernetes.io/job-name"],
    .spec.template.metadata.labels["job-name"]) | .metadata.name += "-rerun-1"' | kubectl create -f -
```

Repeat (`-rerun-2`, …) until the report reads `phase: complete`; every phase is
idempotent and a failed one leaves the v1alpha2 objects in place. Then check
that none of the retired CRDs is left -- all five must be `NotFound`:

```sh
kubectl get crd agents.kagent.dev sandboxagents.kagent.dev agentharnesses.kagent.dev memories.kagent.dev toolservers.kagent.dev
```

Nothing v1alpha2 is deferred past the cut-over: whatever still fails here is
fixed here, before the proofs.

### Step 4 -- the proofs

The installation's cut-over task under giantswarm/giantswarm#37705 lists its
proofs; the standard set is a turn as a signed-in person through the Dev Portal
and through Slack, an agent's toolsets reaching muster as that person, and a
human-in-the-loop approval. The installation is cut over when they pass.

### Afterwards

- Drop the storage-version record once the proofs pass:
  `kubectl -n kagent delete configmap kagent-storage-version-migration`.
- The 0.10 database `kagent` stays for **30 days** on the `kagent-pg` Cluster,
  then is dropped: the fleet template runs the pgvector extension image, so the
  database is a chart-owned CNPG `Database` object and the drop is the value
  `postgres.applicationDatabase.ensure: absent` in the installation's values
  (`UPGRADE.md`, "the cut-over of an installation's database and agents").

### Final advance, after the last installation

When no installation resolves a 3.x meta chart any more, one pull request per
repository: this base's `OCIRepository` range moves to `>=4.0.0 <5.0.0` and the
`HelmRelease` comment on the timeout stays; every per-installation
`OCIRepository` patch is removed; shared-configs flips the Konfiguration default
and drops the conditionals, and every per-installation flag goes with it.

## Dependencies

- dex-app >= 2.1.5 (for muster static client support)
- Gateway API v1 CRDs + a public Gateway to attach muster's HTTPRoute to
- shared-configs with an `agent-platform` app template (renders values
  under the `muster:` umbrella prefix)

## Deploying additional charts into `kagent`

The `agent-platform-connectivity` component renders the `kagent-flux`
ServiceAccount in the `kagent` namespace, bound to the built-in `cluster-admin`
`ClusterRole` via a namespace-scoped `RoleBinding` — i.e. full control of all
resources **within `kagent`** only (see
[Tenant identity of the agents](#tenant-identity-of-the-agents)). The namespace
is this base's (`namespace.yaml`).

Use the identity to deploy additional agent-platform charts as `HelmRelease`s
living in the `kagent` namespace. Unlike the umbrella (which lives in the
policy-exempt `flux-giantswarm`), a `HelmRelease` in `kagent` is subject to the
`flux-multi-tenancy` Kyverno policy, so it **must** set `serviceAccountName` and
target its own namespace:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <chart>
  namespace: kagent
spec:
  serviceAccountName: kagent-flux   # required by flux-multi-tenancy Kyverno policy
  targetNamespace: kagent           # must be local (targetNamespaceMustBeLocal rule)
  ...
```

Because the binding is namespace-scoped, such charts can only create namespaced
resources in `kagent`; cluster-scoped resources (CRDs, ClusterRoles) are denied.

## Creating agents (tenant self-service)

Tenants create agents with the generic
[`agent` chart](https://github.com/giantswarm/agent) 1.x (one Helm release =
one agent), typically as a `HelmRelease` in `kagent` using the `kagent-flux`
ServiceAccount described above. On kagent API v2 a release renders two objects
in the agent's namespace, both named after the agent:

- an **`AgentTemplate`** (`kagent.dev/v1alpha3`) labelled
  `agent-platform.giantswarm.io/harness: kagent`. The label is the admission
  contract: the platform **`Harness`** `kagent` in each managed namespace --
  the Go ADK runtime image by digest, the propagated caller token, the
  Substrate policy (`workerPoolRef` → the WorkerPool `kagent-default`,
  `snapshotPolicy.location` → the installation's snapshot store) -- admits the
  templates carrying it, and a template becomes Ready only when a Harness
  admits it (`status.harnesses[]`). The Harness is rendered by the kagent
  component's release and kept by drift detection; a template without the label
  never becomes Ready.
- a **`RemoteMCPServer`** pointing at muster (`STREAMABLE_HTTP`, the
  `X-Muster-Toolset` header, `kagent.dev/discovery: disabled`), which the
  template binds. There is no shared muster server and no `serverRef` default:
  an `AgentTemplate` binds a `RemoteMCPServer` of its own namespace, and
  agent-manager composes muster's URL into every agent from the platform's one
  helper (`agent-platform.musterMcpUrl`; `agent-manager.muster.url` stays
  unset).

How and where an agent runs is not the agent's: the chart has no `runtime`,
`replicas`, `resources`, `nodeSelector` or `tolerations`. Capacity is the
WorkerPool -- `kagent.substrateWorkerPool.replicas` bounds the concurrently
active agents, `kagent.substrateWorkerPool.template.resources` the size of one
agent's sandbox (one worker hosts one actor at a time); the pool is pinned to one
architecture. Substrate itself (the `atelet` DaemonSet on the worker nodes,
`ate-api-server`, the snapshot store per installation) is part of the kagent
component and lands in `ate-system`.

The admin-owned resources the chart relies on are all rendered by the umbrella
-- **no extra CRs need to be applied via GitOps**:

- **`ModelConfig`s + LLM credentials**: the kagent component renders the
  default `ModelConfig` from `kagent.providers` and creates the provider
  Secret (e.g. `kagent-anthropic`) in the `kagent` namespace from
  `kagent.providers.<provider>.apiKey`, which is SOPS-encrypted per cluster in
  giantswarm-configs under `installations/<mc>/apps/agent-platform/`. Rotate
  the key there; additional catalog entries go in `kagent.modelConfigs`.
- **The kagent API v2 CRDs**, `kagent.dev/v1alpha3`: `agenttemplates`,
  `harnesses`, `modelconfigs`, `modelproviderconfigs`, `remotemcpservers`.
  There is no `agents` CRD -- an agent is an `AgentTemplate` plus the actor
  Substrate runs from it.

## Related

- [agent-platform chart](https://github.com/giantswarm/agent-platform) and its
  [`UPGRADE.md`](https://github.com/giantswarm/agent-platform/blob/main/UPGRADE.md)
- [Generic `agent` chart](https://github.com/giantswarm/agent)
- [Muster MC Deployment Concept](https://github.com/giantswarm/muster/blob/main/docs/concepts/mc-deployment.md)
