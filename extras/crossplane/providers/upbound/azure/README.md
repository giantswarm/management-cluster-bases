# Azure Provider installation

## Quick links

- [Installing crossplane](../../../README.md)
- [Enabling providers and provider family members](../README.md)
- [Setting up a provider](#setting-up-a-provider)
- [Using crossplane with WorkloadIdentity](#using-crossplane-with-workloadidentity)
  - [WebIdentity for crossplane service accounts](./setting-up-workloadidentity.md)
- [Crossplane documentation](https://docs.crossplane.io/)
- [Azure CRD documentation](https://doc.crds.dev/github.com/upbound/provider-azure)

**Warning** These instructions are for Azure only. For AWS and Google Cloud
Platform please see the relevant provider reference documentation linked from
[Enabling providers and provider family members](../README.md).

## Setting up a provider

If `crossplane` has not already been enabled on your management cluster, please
see the [crossplane installation instructions](../../../README.md)

Inside your management clusters repository, you should now have a
`crossplane-providers` sub folder. Inside this, create a subfolder with the API
group of the family you wish to install. For example, if you want to install
`dbforpostgresql.azure.upbound.io` then the directory will be called simply
`dbforpostgresql`.

```nohighlight
crossplane-providers/
├── azure
│   └── kustomization.yaml
└── dbforpostgresql
    └── kustomization.yaml
```

Edit the following `Kustomization` and change all instances of `${PROVIDER}` to
match the directory name. Save this inside the specific provider directory as
`kustomization.yaml`. Set `${VERSION}` to the version you wish to have installed.

For the list of available versions, please see the [crossplane CRD reference
documentation for Azure](https://doc.crds.dev/github.com/upbound/provider-azure).

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/crossplane/providers/upbound/azure?ref=main
patches:
  - patch: |
      - op: replace
        path: /metadata/name
        value: provider-azure-${PROVIDER}
      - op: replace
        path: /spec/serviceAccountName
        value: upbound-provider-azure-${PROVIDER}
    target:
      kind: ControllerConfig
  - patch: |
      - op: replace
        path: /metadata/name
        value: provider-azure-${PROVIDER}
      - op: replace
        path: /spec/controllerConfigRef/name
        value: provider-azure-${PROVIDER}
      - op: add
        path: /spec/package
        value: xpkg.upbound.io/upbound/provider-azure-${PROVIDER}:${VERSION}
    target:
      kind: Provider
  - patch: |
      - op: replace
        path: /metadata/name
        value: upbound-provider-azure-${PROVIDER}
    target:
      kind: ServiceAccount
  - patch: |
     - op: replace
       path: /metadata/name
       value: crossplane-use-psp-upbound-provider-azure-${PROVIDER}
     - op: replace
       path: /subjects/0/name
       value: upbound-provider-azure-${PROVIDER}
    target:
      kind: ClusterRoleBinding
```

## Using crossplane with WorkloadIdentity

To use Azure WorkloadIdentity with crossplane azure providers, both the pod
metadata and the service account first need to be patched with annotations
instructing crossplane on which client to use.

For full details on what annotations and labels may be used for Azure providers
please see the azure documentation [service account labels and annotations](https://azure.github.io/azure-workload-identity/docs/topics/service-account-labels-and-annotations.html).

To patch the pod metadata, add the following ControllerConfig patch:

```yaml
  - patch:
      - op: add
        path: /spec/metadata/annotations/azure.workload.identity~1use
        value: true
    target:
      kind: ControllerConfig
```

This informs the pod that it has the capability of having the workload identity
injected by the workload-identity provider.

Once this is complete, the service account needs to be patched with the client
id that will be used. This client must then have access to all tenants required
for building infrastructure.

```yaml
  - patch:
      - op: add
        path: /metadata/annotations/azure.workload.identity~1client-id
        value: REPLACE_ME_WITH_CLIENT_ID
    target:
      kind: ServiceAccount
```

For detailed instructions on creating a client and tenant, please see the
documentation on [Setting up WorkloadIdentity](./setting-up-workloadidentity.md)
