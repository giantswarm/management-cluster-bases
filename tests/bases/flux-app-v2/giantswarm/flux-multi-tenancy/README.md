## Kyverno Policies Tests

As the title indicates this directory contains Kyverno Policies tests. They have been created to ease adding new policies, without the need of testing live, in cluster, and as such they are not complete at the moment, nor they are not executed automatically as part of the CI pipeline.

To execute test install the [Kyverno CLI](https://kyverno.io/docs/kyverno-cli/install/) and then execute it in this directory with:

```sh
> kyverno test  --detailed-results .
```
