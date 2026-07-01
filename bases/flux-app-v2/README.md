## The `flux-app-v2` base layour

The `flux-app-v2` base is split into three layers. The goal is to keep all version-independent configuration in a single place while allowing the Flux app version to be pinned globally and, when needed, rolled out per management cluster.

```text
bases/flux-app-v2/
├── common/                          # kustomize Component (kind: Component)
│   ├── kustomization.yaml
│   ├── patch-kustomize-controller.yaml
│   ├── resource-namespace.yaml
│   ├── resource-rbac.yaml
│   ├── resource-kyverno-policies.yaml
│   └── resource-kyverno-clusterrole.yaml
├── versions/
│   └── vX.Y.Z/
│       └── kustomization.yaml       # inflates flux-app, pinning a specific chart version
└── giantswarm/
    └── kustomization.yaml           # points at the global/stable version, later consumed by providers
```

The `common` is a version-independent layer, defined as a [Kustomize Component](https://kubectl.docs.kubernetes.io/guides/config_management/components/) holding everything that does not change between Flux app versions like the `flux-giantswarm` namespace, RBAC, Kyverno policies, and the controller patches. It is never built on its own — a version layer mixes it in inside `kustomization.yaml`. This is the single source of truth for the shared configuration.

The `versions/vX.Y.Z` is a specific version layer. Each directory inflates the Flux app Helm Chart pinning one specific chart version (`helmCharts[].version`) and pulls in `common` as a component. To support another version, add a new directory here. The directory name (e.g. `v2.7`) is the Flux version, not the Flux app version (Helm Chart version), because the latter gets released on other ocassions than Flux version changes only and its version although internally pointing to the Flux version, does not reflect it directly. Note, this is the only place the version is decided, because Kustomize cannot override a Helm chart version from a higher layer, so the inflation must happen here.

The `giantswarm` is pointer to the global, considered stable, Flux version. A thin base whose only content is a single resource reference a version base from the `versions/*` directory. It is consumed by all providers and hence the version that is by default reconciled to all management clusters.

**Note:** the `giantswarm` and any of the `versions/*` directory must never both be included in the same management cluster — each inflates the Flux app chart, and two inflations of the same-named resources collide with a duplicate-resource error. A cluster either follows the global version through `giantswarm` (and hence provider), or pins a `versions/*` directory directly, never both.
