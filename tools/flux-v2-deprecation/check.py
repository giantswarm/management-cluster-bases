from io import StringIO

import sh
import yaml
from termcolor import colored
from yaml import FullLoader


def main() -> None:
    check_git_repositories()
    print()
    print("#" * 80)
    print()
    check_kustomizations()


def check_git_repositories() -> None:
    print("Checking gitrepositories.source.toolkit.fluxcd.io across all namespaces...")

    buffer = StringIO()
    sh.kubectl("get", "gitrepositories.source.toolkit.fluxcd.io", "-A", "-o", "yaml", _out=buffer)
    git_repositories = yaml.load(buffer.getvalue(), Loader=FullLoader)

    for git_repository in git_repositories['items']:
        has_errors = False

        print(f"# Checking: {git_repository['metadata']['namespace']}/{git_repository['metadata']['name']}")

        git_implementation = git_repository['spec'].get('gitImplementation')
        if git_implementation:
            if git_implementation == "go-git":
                print(colored(f"  > Warning! .spec.gitImplementation is set to: {git_implementation}", "yellow"))
            else:
                has_errors = True
                print(colored(f"  > Failed! .spec.gitImplementation is set to: {git_implementation}", "red"))

        access_from = git_repository['spec'].get('accessFrom')
        if access_from:
            has_errors = True
            print(colored(f"  > Failed! .spec.accessFrom is set to: {access_from}", "red"))

        if not has_errors:
            print(colored(f"  > Passed!", "green"))


def check_kustomizations() -> None:
    print("Checking kustomizations.kustomize.toolkit.fluxcd.io across all namespaces...")

    buffer = StringIO()
    sh.kubectl("get", "kustomizations.kustomize.toolkit.fluxcd.io", "-A", "-o", "yaml", _out=buffer)
    kustomizations = yaml.load(buffer.getvalue(), Loader=FullLoader)

    for kustomization in kustomizations['items']:
        has_errors = False

        print(f"# Checking: {kustomization['metadata']['namespace']}/{kustomization['metadata']['name']}")

        if kustomization['spec'].get('validation'):
            has_errors = True
            print(colored(f"  > Failed! .spec.validation is set!", "red"))

        if kustomization['spec'].get('patchesStrategicMerge'):
            has_errors = True
            print(colored(f"  > Failed! .spec.patchesStrategicMerge is set! Should be moved to .spec.patches!", "red"))

        if kustomization['spec'].get('patchesJson6902'):
            has_errors = True
            print(colored(f"  > Failed! .spec.patchesJson6902 is set! Should be moved to .spec.patches!", "red"))

        if not has_errors:
            print(colored(f"  > Passed!", "green"))


if __name__ == '__main__':
    main()
