## The `flux-migration` base

Upgrading Flux across some minor versions (e.g. `v2.6` -> `v2.7`) requires running `flux migrate` **before** the new CRDs are applied, so that stored objects are moved to the new storage version before the old CRD versions are dropped. In our setup CRDs and the Flux app are delivered by two separate Flux `Kustomization` CRs, so the migration needs its own step that runs ahead of both.

This base holds those migration steps, one directory per transition, plus a global pointer that mirrors the `flux-app-v2` and `crds/flux-app-v2` layout:

```text
bases/flux-migration/
├── kustomization.yaml              # global/stable toggle, empty by default (no-op)
└── versions/
    └── vX.Y.Z/
        ├── kustomization.yaml      # includes the migration Job
        └── job-migrate.yaml        # runs `flux migrate` for that transition
```

### How the ordering is enforced

A dedicated `flux-migration` Flux `Kustomization` (see the `flux-giantswarm-resources/resource-kustomizations.yaml`) delivers this base, and the `crds` Kustomization depends on it. Because `flux-migration` has `wait: true`, it only becomes `Ready` once the migration Job has **completed successfully** — so `crds` does not apply new CRDs until the migration has run, and `flux` (which depends on the `crds` Kustomization CR) does not roll the app until after that. The resulting order is:

```text
flux-migration (Job completes)  ->  crds  ->  flux
```

If the Job fails, `flux-migration` never becomes `Ready`, `crds` stays blocked, and the upgrade halts safely instead of applying CRDs without a migration. But truth to be told, doing that wouldn't cause any damage for Kubernetes has its own safeguards against applying CRDs which try to remove stored versions.

### The Job

The Job is extracted from the Flux app Helm Chart's pre-upgrade hook and delivered as a plain manifest. Two deliberate differences from the chart's hook version:

The Job name is pinned to the target version (`flux-app-flux-migrate-2-7-5`), so it runs exactly once per transition. If a migration fails and you need to re-run it after a fix, delete the failed Job manually (Jobs are immutable) so GitOps recreates it.

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
