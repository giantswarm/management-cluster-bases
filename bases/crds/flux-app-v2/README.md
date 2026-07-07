## The `crds/flux-app-v2` base layout

The `crds/flux-app-v2` base holds the Flux CRDs and is split into layers that mirror the [`flux-app-v2`](../../flux-app-v2/README.md) (app) base. The goal is to keep the CRD manifests versioned in their own directories while allowing the CRD version to be pinned globally and, when needed, rolled out per management cluster. It must stay in lockstep with the app base - an app `versions/vX.Y` generally requires the matching CRD `versions/vX.Y` (e.g. Flux `v2.7` adds the `ExternalArtifact` CRD).

```text
bases/crds/flux-app-v2/
├── kustomization.yaml              # points at the global/stable version, consumed by the CRD stages
└── versions/
    └── vX.Y.Z/
        ├── kustomization.yaml      # labels the CRDs with the Flux app version and includes crds.yaml
        └── crds.yaml               # the Flux CRD manifests for that version
```

The `versions/vX.Y.Z` is a specific version layer. Each directory includes the `crds.yaml` manifests for one Flux version and stamps them with the `app.kubernetes.io/version` label. To support another version, add a new directory here. The directory name (e.g. `v2.7`) is the upstream Flux minor version, matching the app base's `versions/*` so the two stay aligned. Unlike the app base, these are plain manifests rather than a Helm chart, so there is no inflation constraint — the layout is kept symmetric with the app base purely for consistency.

The `kustomization.yaml` at the base root is a pointer to the global, considered stable, CRD version. A thin kustomization whose only content is a single resource referencing a version directory from `versions/*`. It is consumed by the CRD stages (`crds/common-flux-v2/stages/*`) and hence is the version that is by default reconciled to all management clusters — the CRD-side counterpart of the app base's `giantswarm` pointer.

Each stage factors `flux-operator` and `giantswarm/stages/<stage>` into a `core` directory, keeping the `flux-app-v2` pointer alongside it. A stage can therefore pin a specific CRD version by referencing a `versions/*` directory instead of the pointer. However this effectively allows us staging Flux CRDs, similar staging is not yet supported in providers bases, hence staging the Flux app as a whole is not possible at the moment.

**Note:** the pointer and any of the `versions/*` directories must never both be included in the same management cluster — each renders the same CRD manifests, and two copies of the same-named resources collide with a duplicate-resource error. A cluster either follows the global version through the pointer (and hence the stage), or pins a `versions/*` directory directly, never both.
