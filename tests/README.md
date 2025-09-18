## MCB Tests

The purpose of this directory is to gather various tests for bases kept in the repository.

One may wonder of why a separate directory had to be created for tests, while they could equally good be part of respective bases. The reason is Flux.

Tests may contain testing resources, which creation should never be attempted in any cluster. Due to that having them part of bases felt risky in the face of Flux's feature of building the `kustomization.yaml` dynamically for objects it recursively finds in a given directory, in case a pre-defined `kustomization.yaml` does not exist.

As a matter of fact, these days Flux does not reconcile this repository directly, for as the name indicates it rather serves as a collection of bases to be referenced in other places. But this said, possibility to reconcile something from it directly is not prohibited in any way, and hence someone may try it in the future. In such case it would be much safer to make sure the `tests` directory inside a base is not treated as a collection of objects to deliver in case this base directory does not have its own `kustomization.yaml`. And the easiest way was to not make tests part of bases.
