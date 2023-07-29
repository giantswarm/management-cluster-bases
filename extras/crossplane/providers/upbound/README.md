# Enabling providers and provider family members

__Note__ These providers are not intended to be installed directly but instead
should be patched into your management-clusters repository on a per-management
cluster basis.

With the changes to `crossplane` brought about in version v1.12.0, GiantSwarm
will no longer be directly managing providers but instead we'll be offering a
simplified process to installing new providers inside your cluster.

## Installation

For detailed instructions on the provider(s) for your environment please see the
relevant documentation:

- [upbound-provider-aws](./aws)
- [upbound-provider-azure](./azure)
- [upbound-provider-gcp](./gcp)

## Enabling alpha functionality

Although normally not recommended, occasionally you may wish to experiment with
alpha functionality such as `managementPolicies` for using `ObserveOnly` resources.

To enable additional functionality at the provider level, add the following
patch to the `ControllerConfig`, setting one or more alpha/beta functionality
flags as appropriate for the provider you are installing.

```yaml
  - patch: |
      - op: replace
        path: /spec/args
        value:
          --debug
          --alpha-function-flag
    target:
      kind: ControllerConfig
```

__Note__ At present there is no centralised list of alpha/beta flags that may
be given to a provider. For ones that may be available, refer to the [crossplane
documentation](https://docs.crossplane.io/).

## Enabling additional providers

We offer simplified bases for each of the major cloud providers, although there
are no limitations on the providers you may install.

We do however strongly recommend that you discuss your requirements with us
prior to enabling new providers on your cluster so we can help you assess if there
will be any security or performance impacts as a result of the providers you
require for your configuration.
