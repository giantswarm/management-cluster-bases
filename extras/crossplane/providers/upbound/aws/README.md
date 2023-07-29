# AWS Provider installation

## Quick links

- [Installing crossplane](../../../README.md)
- [Enabling providers and provider family members](../README.md)
- [Setting up a provider](#setting-up-a-provider)
- [Using crossplane with IRSA](#using-crossplane-with-iam-roles-for-service-accounts)
  - [IAM Roles for crossplane service accounts](./setting-up-irsa.md)
- [Crossplane documentation](https://docs.crossplane.io/)
- [AWS CRD documentation](https://doc.crds.dev/github.com/upbound/provider-aws)

**Warning** These instructions are for AWS only. For Azure and Google Cloud
Platform please see the relevant provider reference documentation linked from
[Enabling providers and provider family members](../README.md).

## Setting up a provider

If `crossplane` has not already been enabled on your management cluster, please
see the [crossplane installation instructions](../../../README.md)

Inside your management clusters repository, you should now have a
`crossplane-providers` sub folder. Inside this, create a subfolder with the API
group of the family you wish to install. For example, if you want to install
`ec2.aws.upbound.io` then the directory will be called simply `ec2`.

```nohighlight
crossplane-providers/
├── ec2
│   └── kustomization.yaml
├── kms
│   └── kustomization.yaml
└── rds
    └── kustomization.yaml
```

> **Note** Once the `crossplane-providers/PROVIDER/kustomization.yaml` file has
> been created, it is safe to delete the `crossplane-providers/kustomization.yaml`
> file as this will be handled transparently by the
> [`crussplane-providers`](https://github.com/giantswarm/management-cluster-bases/blob/main/extras/crossplane/providers-kustomization.yaml)
> flux `kustomization`.
>
> If you do not delete this file, you must ensure that your provider is added
> to the list of resources referenced by
> `CUSTOMER_NAME-management-clusters/management-clusters/MC_NAME/crossplane-providers/kustomization.yaml`.
>
> ```yaml
> resources:
>   - ec2
>   - kms
>   - rds
> ```

Edit the following `Kustomization` and change all instances of `${PROVIDER}` to
match the directory name. Save this inside the specific provider directory as
`kustomization.yaml`. Set `${VERSION}` to the version you wish to have installed.

For the list of available versions, please see the [crossplane CRD reference
documentation for AWS](https://doc.crds.dev/github.com/upbound/provider-aws).

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/crossplane/providers/upbound/aws?ref=main
patches:
  - patch: |
      - op: replace
        path: /metadata/name
        value: provider-aws-${PROVIDER}
      - op: replace
        path: /spec/serviceAccountName
        value: upbound-provider-aws-${PROVIDER}
    target:
      kind: ControllerConfig
  - patch: |
      - op: replace
        path: /metadata/name
        value: provider-aws-${PROVIDER}
      - op: replace
        path: /spec/controllerConfigRef/name
        value: provider-aws-${PROVIDER}
      - op: add
        path: /spec/package
        value: xpkg.upbound.io/upbound/provider-aws-${PROVIDER}:${VERSION}
    target:
      kind: Provider
  - patch: |
      - op: replace
        path: /metadata/name
        value: upbound-provider-aws-${PROVIDER}
    target:
      kind: ServiceAccount
  - patch: |
     - op: replace
       path: /metadata/name
       value: crossplane-use-psp-upbound-provider-aws-${PROVIDER}
     - op: replace
       path: /subjects/0/name
       value: upbound-provider-aws-${PROVIDER}
    target:
      kind: ClusterRoleBinding
```

## Using `crossplane` with IAM Roles for Service Accounts

If you wish to use `IRSA` with the provider (recommended) you will first need
to set up a primary `AssumeRoleWithWebIdentity` for the crossplane service
accounts to inherit.

For detailed instructions on setting up the primary IAM role, please see the
documentation on [IAM roles for crossplane service accounts](./setting-up-irsa.md)

Once this role is available, the following patch needs to be applied to the
`ServiceAccount` used by the provider you are installing.

```yaml
  - patch: |
      - op: add
        path: /metadata/annotations/eks.amazonaws.com~1role-arn
        value: arn:aws:iam::${AWS_ACCOUNT_ID}:role/crossplane-assume-role
    target:
      kind: ServiceAccount
```
