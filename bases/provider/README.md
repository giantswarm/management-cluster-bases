# Provider bases

## Pinning Flux version per-cluster

Each providers' `flux-v2` directory bundles the Flux app instance together with the rest of the core provider configuration, so on its own each always renders the global, considered stable, Flux app version and its resources. Internally however, this directory is split into two parts, a `core` part and `flux-app-v2` base reference part:

```text
bases/provider/PROVIDER/flux-v2/
├── kustomization.yaml        # full base: ./core + ../../../flux-app-v2/giantswarm
└── core/                     # the flux-less part
    ├── kustomization.yaml    # everything the provider needs except flux-app
    └── configmap-provider-data.yaml
```

The `core` contains everything the provider contributes *except* the Flux app instance (`flux-giantswarm-resources`, `flux-operator`, the release definitions, and the provider `configmap-provider-data.yaml`). It renders no Flux app controllers.

The `flux-v2` is `core` plus `flux-app-v2/giantswarm` (the global, considered stable version). This is what a management cluster references by default, and its rendered output is unchanged by the split.

To pin a version on one cluster, that cluster's kustomization references `provider/PROVIDER/flux-v2/core?ref=main` **and** a `flux-app-v2/versions/*` directory instead of the full `flux-v2` base. This way, the cluster still gets the latest configuration coming from the Management Cluster Bases, but yet runs a different version of Flux. Because `core` carries no flux-app, there is exactly one flux-app inflation and no duplicate-resource collision.

Reverting the changes, for example, when all other MCs have been finally migrated to the latest, stable, Flux app version, requires only switching back to the `flux-v2` base.
