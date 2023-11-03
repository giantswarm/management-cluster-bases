# Crossplane

To enable [crossplane](https://docs.crossplane.io/) on your management cluster
this base should be used.

If crossplane is already enabled on your management cluster and you wish to
install providers, please see the additional documentation under
[providers/upbound](./providers/upbound)

> **Warning** All operations carried out as part of this enablement set are
> carried out on your `CUSTOMER_NAME-management-clusters` repository.
>
> Do not raise PRs to enable crossplane on your management cluster against this
> repository. It will neither work, nor be accepted.
>
> If you do not know what your `CUSTOMER_NAME-management-clusters` repository is
> please talk to your account engineer.

This base provides a generalised template for deploying crossplane core to your
management cluster using versions of crossplane that have been tested by
ourselves and are guaranteed to work inside our environment.

Inside your management-clusters repository, you will find a structure such as:

```nohighlight
.
├── bases
│   ├── flux-app
│   │   └── crds
│   │       └── kustomization.yaml
│   └── patches
│       └── kustomization-post-build.yaml
├── management-clusters
│   └── MC_NAME
│       ├── catalogs
│       │   ├── kustomization.yaml
│       │   └── patches
│       │       └── ...
│       ├── configmap-management-cluster-metadata.yaml
│       ├── extras
│       │   └── kustomization.yaml
...
```

The `Kustomization` we're interested in is `management-clusters/MC_NAME/extras`

## Kustomization

Open the `kustomization.yaml` file and add the following information. Take care
to only append this information to existing sections to ensure existing resources
are not accidentally removed from your cluster.

Replace all instances of `MC_NAME` with the name of your management cluster.

```yaml
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/crossplane/?ref=main
patches:
  - patch: |
      apiVersion: kustomize.toolkit.fluxcd.io/v1
      kind: Kustomization
      metadata:
        name: crossplane-providers
        namespace: flux-giantswarm
      spec:
        path: "./management-clusters/MC_NAME/crossplane/providers"
        postBuild:
          substitute:
            awsversion: 0.43.1
            kubernetesversion: 0.9.0
            azureversion: 0.0.0
            gcpversion: 0.0.0
    target:
      kind: Kustomization
      name: crossplane-providers
      namespace: flux-giantswarm
  - patch: |
      apiVersion: kustomize.toolkit.fluxcd.io/v1
      kind: Kustomization
      metadata:
        name: crossplane-compositions
        namespace: flux-giantswarm
      spec:
        path: "./management-clusters/MC_NAME/crossplane/compositions"
    target:
      kind: Kustomization
      name: crossplane-compositions
      namespace: flux-giantswarm
  - patch: |
      apiVersion: kustomize.toolkit.fluxcd.io/v1
      kind: Kustomization
      metadata:
        name: crossplane-claims
        namespace: flux-giantswarm
      spec:
        path: "./management-clusters/MC_NAME/crossplane/claims"
    target:
      kind: Kustomization
      name: crossplane-claims
      namespace: flux-giantswarm
```

### Patches

In the above sample, there are 3 patches used with each patch depending on
the previous one.

For example: 

- `crossplane-claims` depends on
- `crossplane-compositions` depends on
- `crossplane-providers`

This is set up in this manner to ensure that claims are not applied before
providers and compositions are ready which would result in a failed build
due to CRDs being missing from the platform.

Inside the `postBuild` section in the first (`crossplane-providers`) patch,
the substitutions are:

- `awsversion` This is the version of the AWS provider to apply consistently
  across all provider family members
- `kubernetesversion` This is the version to use of the 
  `crossplane-contrib/provider-kubernetes` provider. This is a helper here as
  this provider must be setup entirely from within your 
  `CUSTOMER_NAME-management-clusters` respository.
- `azureversion` This is the version of the azure provider to apply to the
  management cluster
- `gcpversion`

It is recommended that all version strings are defaulted such as: 
`${awsversion:=0.43.0}` This ensures that at least a minimum provider version
will always be used.

> **Note**
>
> You do not need to specify the preceeding `v` to version strings. All 
> examples given provide this as part of the mapping.

## Crossplane provider setup

To set up the providers we must first create the structure for the
kustomizations to use

```bash
mkdir -p management-clusters/MC_NAME/crossplane/{providers/{aws/{providers,functions},kubernetes},compositions,claims}
tee <<<"resources: []" management-clusters/MC_NAME/crossplane/{providers/{aws/{providers,functions},kubernetes},compositions,claims}/kustomization.yaml
```

This will give you a heirarcy of:

```nohighlight
.
└── management-clusters
    └── MC_NAME
        └── crossplane
            ├── claims
            │   └── kustomization.yaml
            ├── compositions
            │   └── kustomization.yaml
            └── providers
                ├── aws
                │   ├── functions
                │   │   └── kustomization.yaml
                │   └── providers
                │       └── kustomization.yaml
                └── kubernetes
                    └── kustomization.yaml
```

> **Note**
>
> The following assumes the AWS provider will be used. For Azure or GCP, replace
> all instances of `aws` with the provider you wish to use. Must be one of
> `aws`, `azure`, `gcp`

Open the `management-clusters/MC_NAME/crossplane/providers/aws/kustomization.yaml`
file and replace `resources: []` with the following contents:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/giantswarm/management-cluster-bases//extras/crossplane/providers/upbound/aws?ref=upgrade-crossplane-1.14
  - functions
  - providers
patches:
  - patch: |
      - op: replace
        path: /metadata/name
        value: upbound-provider-aws
      - op: replace
        path: /spec/deploymentTemplate/spec/template/spec/serviceAccountName
        value: upbound-provider-aws
    target:
      kind: DeploymentRuntimeConfig
      labelSelector: provider-family-member=aws-provider
  - patch: |
      - op: replace
        path: /metadata/name
        value: upbound-provider-aws

        # Only relevant if you are using IRSA to authenticate to
        # AWS. Leave this out if not required.
      - op: add
        path: /metadata/annotations/eks.amazonaws.com~1role-arn
        value: arn:aws:iam::<ACCOUNT_ID>:role/crossplane-assume-role
    target:
      kind: ServiceAccount
      labelSelector: provider-family-member=aws-provider
  - patch: |
     - op: replace
       path: /metadata/name
       value: crossplane-use-psp-upbound-provider-aws
     - op: replace
       path: /subjects/0/name
       value: upbound-provider-aws
    target:
      kind: ClusterRoleBinding
      labelSelector: psp-binding=true
```

If you're using IRSA to connect crossplane to the cloud account, remember to
change `<ACCOUNT_ID>` to the value of your account. If you do not know your
account ID, you can find this with:

```bash
aws sts get-caller-identity --profile localsnail  | jq .Account
```

alternatively, ask your cloud admin.

### Enabling providers

As an example, we will enable the `upbound/provider-aws-ec2` provider on your
management cluster.

Create a new file `ec2.yaml` at `management-clusters/MC_NAME/crossplane/providers/aws/providers`
with the following contents

```yaml
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: upbound-provider-aws-ec2
  namespace: crossplane
spec:
  ignoreCrossplaneConstraints: false
  packagePullPolicy: IfNotPresent
  revisionActivationPolicy: Automatic
  revisionHistoryLimit: 0
  skipDependencyResolution: false
  package: xpkg.upbound.io/upbound/provider-aws-ec2:v${awsversion:=0.43.0}
  runtimeConfigRef:
    name: upbound-provider-aws
```

Next, add this to the `kustomization.yaml` in the same directory to ensure
it is deployed correctly.

```yaml
resources:
- ec2.yaml
```

Commit these changes to git and raise a PR to have this merged into the main
branch. Once your PR is accepted and merged, crossplane will deploy to your
management cluster during the next full reconcilliation cycle.

If you then list pods in the `crossplane` namespace, you should see the `ec2`
provider come to life after a few minutes.

```nohighlight
k get po -n crossplane
NAME                                                              READY   STATUS    RESTARTS   AGE
caicloud-event-exporter-d69c94668-k75cs                           1/1     Running   0          7m
crossplane-6454dd6bbb-54jwx                                       1/1     Running   0          7m
crossplane-rbac-manager-848b46f587-hzfp9                          1/1     Running   0          7m
upbound-provider-aws-ec2-4805a8dbe18c-5ff4fcc7fb-gklhj            1/1     Running   0          5m
upbound-provider-family-aws-a64e2d8b178a-69d679458b-xvlrn         1/1     Running   0          6m
```

### Enabling composition functions

In this example we will enable the `patch-and-transform` function from the 
`crossplane-contrib` repository.

Create a new file `patch-and-transform.yaml` at `management-clusters/MC_NAME/crossplane/providers/aws/functions`
with the contents:

```yaml
---
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-patch-and-transform
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:v0.1.4
  runtimeConfigRef:
    name: upbound-provider-aws
```

Next, add this to the `resources` section of `kustomization.yaml` 

```yaml
resources:
- patch-and-transform.yaml
```

Save and commit this. You should see the `patch-and-transform` function start 
on the next reconciliation cycle.

```nohighlight
function-patch-and-transform-201f894df2f6-6fb8dff6fc-lftnj        1/1     Running   0          56s
```

## Enabling compositions

Once you have all your providers installed, the next step is to enable 
compositions within your cluster.

We understand that your compositions may be hosted in your own repositories
however where this may be the case, they must be public facing or flux may be
unable to access them.

Open the file `management-clusters/MC_NAME/crossplane/compositions/kustomization.yaml`
and under resources, add either a path to, or a URL to the compositions.

For example, to enable the `postgres` compositions from our [`crossplane-examples`](https://github.com/giantswarm/crossplane-examples)
repository, the kustomization will look like:

```yaml
resources:
- https://github.com/giantswarm/crossplane-examples/aws-provider/postgresdb/xrd?ref=main
```

> **Note**
>
> The (remote) composition directory **must** contain a `kustomization.yaml` 
> file listing all the files that should be included from that location.

Commit this change and apply. You should see the composition and definition
appear on the next reconciliation cycle.

## Enabling claims

Claims should be copied into the `management-clusters/MC_NAME/crossplane/claims`
directory and enabled in the `kustomization.yaml` file. Similarly to 
compositions they may also come from a remote URL however as they often contain 
data considered to be more sensitive, it is not recommended that they are
stored publically.

## Enabling alpha and beta flags to crossplane

Crossplane supports additional feature flags for enabling alpha and beta
functionality to the crossplane pod.

**Warning** We do not advise running this on any crossplane installation handling
production workloads. This must only ever be used for testing purposes.

Edit the `management-clusters/MC_NAME/extras/kustomization.yaml` and append the
following patch.

```yaml
  - op: add
    path: /spec/values/args
    value:
      - --beta-feature-flag
      - --alpha-feature-flag
    target:
      kind: HelmRelease
      name: crossplane
      namespace: flux-giantswarm
```
