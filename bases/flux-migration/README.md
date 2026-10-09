## The `flux-migration` base

Upgrading Flux across some minor versions (e.g. `v2.6` -> `v2.7`) requires running `flux migrate` **before** the new CRDs are applied, so that stored objects are moved to the new storage version before the old CRD versions are dropped. In our setup CRDs and the Flux app are delivered by two separate Flux `Kustomization` CRs, so the migration needs its own step that runs ahead of both.

This base holds those migration steps, one directory per transition, plus a global pointer that mirrors the `flux-app-v2` and `crds/flux-app-v2` layout:

```text
bases/flux-migration/
├── kustomization.yaml              # global/stable toggle, empty by default (no-op)
├── template/
│   ├── kustomization.yaml
│   └── job-migrate.yaml            # the shared migration Job (all the boilerplate)
└── versions/
    └── vX.Y.Z/
        └── kustomization.yaml      # thin overlay: sets name suffix, image tag, --version
```

The migration Job is almost identical between transitions, so the full manifest lives once in `template/`, and each `versions/<vX.Y>` overlay changes only the three values that actually differ: the run-once name suffix, the flux-cli image tag (target version), and the `--version` argument (the version to migrate FROM). Adding support for a new transition is a small overlay, e.g.:

```yaml
resources:
  - ../../template
nameSuffix: -2-8-0
images:
  - name: gsoci.azurecr.io/giantswarm/flux-cli
    newTag: v2.8.0
patches:
  - target:
      kind: Job
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/args
        value:
          - migrate
          - --version=2.7
```

### How the ordering is enforced

A dedicated `flux-migration` Flux `Kustomization` (see the `flux-giantswarm-resources/resource-kustomizations.yaml`) delivers this base, and the `crds` Kustomization depends on it. Because `flux-migration` has `wait: true`, it only becomes `Ready` once the migration Job has **completed successfully** — so `crds` does not apply new CRDs until the migration has run, and `flux` (which depends on the `crds` Kustomization CR) does not roll the app until after that. The resulting order is:

```text
flux-migration (Job completes)  ->  crds  ->  flux
```

If the Job fails, `flux-migration` never becomes `Ready`, `crds` stays blocked, and the upgrade halts safely instead of applying CRDs without a migration. But truth to be told, doing that wouldn't cause any damage for Kubernetes has its own safeguards against applying CRDs which try to remove stored versions.

### Limitation: objects that are not Ready

`flux-migration` runs with `wait: true` and `timeout: 10m`, so Flux health-checks **every** object the Kustomization applies, not only the migration Job. An object that is not `Ready` (for example an `MCPServer` that is suspended, `Ready=False` with reason `Suspended`) keeps `flux-migration` not ready until the timeout, and every Kustomization that depends on it, directly or transitively (`crds`, `flux`, `catalogs`, `crossplane-*`, `flux-extras`, `silences`, ...), reports not ready meanwhile. That fires `FluxKustomizationFailed` for each of them, repeatedly, and the upgrade chain stalls.

So this base is for the migration Job only. Do not use the cluster's `flux-migration` directory to adopt objects that are, or may stay, not Ready. Preferably adopt them in a Kustomization that does not gate others. If it has to be done here, use one of the recipes below.

**Recipe 1: adopt only Ready objects.** Make sure the object is `Ready` before it enters the `flux-migration` directory (for a suspended one, unsuspend it first). A revision with only healthy objects passes the health check and the dependants stay Ready. If an unhealthy object was adopted by mistake, remove it again in a follow-up commit: the chain stays blocked until the timeout in the meantime, so prefer getting it right the first time.

**Recipe 2: scope the health check while adopting.** Keep the object, but stop `wait` from covering it. In the cluster's `flux-migration` Kustomization CR either list only what must be healthy,

```yaml
spec:
  wait: false
  healthChecks:
    - apiVersion: batch/v1
      kind: Job
      name: flux-app-flux-migrate-2-7-5
      namespace: flux-giantswarm
```

(per the [Flux `Kustomization` reference](https://fluxcd.io/flux/components/kustomize/kustomizations/#wait), `wait: true` health-checks every applied object and makes `healthChecks` redundant, hence `wait: false`), or set `wait: false` without `healthChecks` for the duration of the adoption, which makes the Kustomization Ready as soon as the apply succeeded. In the latter case `crds` no longer waits for the migration Job to complete, so only do it when no migration is pending; revert it afterwards.

### The Job

The Job (`template/job-migrate.yaml`) is extracted from the Flux app Helm Chart's pre-upgrade hook and delivered as a plain manifest.

The Job name, when the Job gets instantiated, is pinned to the target version (`flux-app-flux-migrate-2-7-5`), so it runs exactly once per transition. If a migration fails and you need to re-run it after a fix, delete the failed Job manually (Jobs are immutable) so GitOps recreates it.

### Running a migration

There are two ways to trigger a migration, matching the app and CRD bases.

**The first is global (all clusters at once)** — a cluster's `management-clusters/<MC_NAME>/flux-migration` directory references the global pointer by
default:

```yaml
resources:
  - https://github.com/giantswarm/management-cluster-bases//bases/flux-migration?ref=main
```

To migrate the whole fleet, add the version to the global toggle here (`bases/flux-migration/kustomization.yaml`), i.e. set `resources` to `./versions/v2.7` (it is empty by default). Every cluster following it picks it up. Once the fleet has migrated, empty it again so the completed Jobs are pruned and newly-created clusters do not run a stale migration.

**The second is per-cluster (canary)** — point a single cluster's `flux-migration` directory at a specific version instead of the global pointer:

```yaml
resources:
  - https://github.com/giantswarm/management-cluster-bases//bases/flux-migration/versions/v2.7?ref=main
```

In both cases, once the Job has completed, proceed with the CRD and app version bumps for those clusters. And also in both cases **thanks to having three Kustomization CRs managing each Flux app part it is safe to do all the switch to a new version in a single PR.**

> **Note:** as with the app and CRD bases, a cluster must reference **either** the global pointer **or** a `versions/*` directory, never both — the migration Job is the same named resource and two copies collide with a duplicate-resource error.

> **Warning:** the Flux storage migration is effectively one-way. Once CRDs are switched to the new version, rolling the app back is not clean. Treat the CRD switch as a point of no return and canary on a test MC first.
