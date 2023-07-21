# Enabling providers and provider family members

> **Note** These providers are not intended to be installed directly.
>
With the changes to `crossplane` brought about in version v1.12.0, GiantSwarm
will no longer be directly managing providers but instead we'll be offering a
simplified process to installing new providers inside your cluster.

For the moment this is limited to the major cloud providers

- upbound-provider-aws
- upbound-provider-azure
- upbound-provider-gcp

We currently do not support the community contributed providers. If you have a
use case for this, or for another provider, we encourage you to talk to us first.

## Provider installation

In the git repository relating to your management cluster, you will find a
folder `crossplane-providers`. If this does not exist let us know and crossplane
will be enabled for you.

Inside this folder, create a subfolder with the API group of the family you
wish to install. For example, if you want to install `ec2.aws.upbound.io` then
the directory will be called simply `ec2`.

Edit the following `Kustomization` and change all instances of `${PROVIDER}` to
match the directory name. Save this inside the provider directory as
`kustomization.yaml`

> **Warning** This example is for AWS only. For Azure and GCP make sure you
> adapt the provider names and annotations accordingly

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
        value: xpkg.upbound.io/upbound/provider-aws-${PROVIDER}:v0.37.0
    target:
      kind: Provider
  - patch: |
      - op: replace
        path: /metadata/name
        value: upbound-provider-aws-${PROVIDER}
      - op: add
        path: /metadata/annotations/eks.amazonaws.com~1role-arn
        value: arn:aws:iam::${AWS_ACCOUNT_ID}:role/crossplane-assume-role
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

For setup and configuration of IAM, please see the example documentation in the
[crossplane-examples](https://github.com/giantswarm/crossplane-examples/blob/add-aws-crossplane/aws-provider/postgresdb/README.md)
repo.
