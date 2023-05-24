# management-cluster-bases

Giant Swarm management cluster bases.

## Layout

- `bases` holds definitions for both Flux deployments
    - `flux-app/customer` is the `flux-app` instance deployed to `flux-system`,
      plus all the additional RBAC, Kyverno policies etc.
    - `flux-app/giantswarm` is the `flux-app` instance deployed to
      `flux-giantswarm` with necessary patches, RBAC, K8s resources.
    - `flux-giantswarm-resources` holds Flux CRs first created in
      `flux-giantswarm` Namespace when the Management Cluster is bootstrapped.
      This helps `mc-bootstrap` apply resources in stages (first Flux and CRDs, then
      its resources)
    - `provider` holds definitions for all the individual providers we serve.
      `kustomization.yaml` in there should reference all three bases in
      `bases/flux-app`.
- `extras` is a place to define patches, additional resources, and mix-ins used
  by **more than one** MC.
