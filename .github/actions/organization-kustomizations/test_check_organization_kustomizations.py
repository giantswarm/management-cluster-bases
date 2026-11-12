#!/usr/bin/env python3
"""Tests for check-organization-kustomizations.py, run as CI runs it.

Run: python3 -m unittest discover -s .github/actions/organization-kustomizations -p 'test_*.py'
"""
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-organization-kustomizations.py")
ORGS = "management-clusters/graveler/extras/agent-platform-organizations"
ORG = f"{ORGS}/content/team-a/alpha"
OTHER = f"{ORGS}/content/team-a/beta"
KUSTOMIZATION = f"{ORG}/kustomization.yaml"


def kustomization(body):
    return "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n" + textwrap.dedent(body)


# Every case has the other organization's ciphertext next door, the file an escape would reach.
BASE_FILES = {
    f"{ORG}/modelconfig-claude.yaml": "kind: ModelConfig\n",
    f"{ORG}/tenant-credential-x-secret.enc.yaml": "kind: Secret\n",
    f"{ORG}/patches/modelconfig.yaml": "kind: ModelConfig\n",
    f"{OTHER}/tenant-credential-y-secret.enc.yaml": "kind: Secret\n",
}

GIT_URL = "kustomize reads it as a git repository URL and clones it"
HTTP_URL = "kustomize reads it as an HTTP URL and downloads it"
CHARACTER = "a character other than a letter, a digit, '.', '_', '-' or '/'"
ALLOWED = "allowed: a relative path to a file or directory inside this directory"
FIELDS_ALLOWED = "only apiVersion, kind, metadata and resources are allowed"


def local_base(dirname):
    """A directory `dirname` in the organization's path that holds a valid kustomization.

    The check then sees an existing local directory. kustomize tries a directory entry as
    a git URL before it reads it from disk, so a name that is a git URL is cloned.
    """
    return {
        f"{ORG}/{dirname}/kustomization.yaml": kustomization("resources:\n- cm.yaml\n"),
        f"{ORG}/{dirname}/cm.yaml": "kind: ConfigMap\n",
    }


# Remote entries, as kustomize-controller v1.7.3 reads them. Its go.mod replaces
# sigs.k8s.io/kustomize/api with v0.20.1 (kustomize v5.7.1). In that version:
# - internal/target/kusttarget.go L418-L427 (accumulateResources) reads a `resources` entry
#   as a file first and, if that fails (a directory, for one), as a new root.
# - internal/loader/fileloader.go L21-L26 (IsRemoteFile) and L293-L296 (Load): a file whose
#   Go url.Parse scheme is "http" or "https" (any case) is downloaded.
# - internal/loader/fileloader.go L152-L165 (New): a root for which
#   internal/git/repospec.go NewRepoSpecFromURL succeeds is cloned, before the local
#   directory is looked at. repospec.go L252-L387 (extractHost) accepts: an optional "git::"
#   prefix (any case); then the scheme "ssh://", "https://", "http://" or "file://" (any
#   case); or no scheme and a user "^[a-zA-Z][a-zA-Z0-9-]*@" (SCP style, "user@host:path"
#   or "user@host/path"); or no scheme and "github.com/" or "github.com:" (any case).
#   L79 and L213-L250: "?ref=" and "?version=" select the reference.
# The cases with local_base() are directories that exist in the organization's path, so
# only the URL rule refuses them.
REMOTE_CASES = {
    "git URL: github.com with // and ?ref=": (
        {KUSTOMIZATION: kustomization("resources:\n- github.com/giantswarm/x//deploy?ref=v1\n")},
        {}, 1, [GIT_URL]),
    "git URL: https github.com": (
        {KUSTOMIZATION: kustomization("resources:\n- https://github.com/giantswarm/x/deploy?ref=v1\n")},
        {}, 1, [GIT_URL]),
    "git URL: git:: prefix (go-getter style)": (
        {KUSTOMIZATION: kustomization("resources:\n- git::https://github.com/giantswarm/x.git//deploy?ref=v1\n")},
        {}, 1, [GIT_URL]),
    "git URL: SCP style git@github.com:": (
        {KUSTOMIZATION: kustomization("resources:\n- git@github.com:giantswarm/x.git/deploy?ref=v1\n")},
        {}, 1, [GIT_URL]),
    "git URL: ssh://": (
        {KUSTOMIZATION: kustomization("resources:\n- ssh://git@github.com/giantswarm/x.git/deploy\n")},
        {}, 1, [GIT_URL]),
    "git URL: another host with ?version=": (
        {KUSTOMIZATION: kustomization("resources:\n- https://gitlab.example.com/org/x.git//deploy?version=v1\n")},
        {}, 1, [GIT_URL]),
    "git URL: Azure _git/": (
        {KUSTOMIZATION: kustomization("resources:\n- https://user@dev.azure.com/org/project/_git/x/deploy\n")},
        {}, 1, [GIT_URL]),
    "git URL: file://": (
        {KUSTOMIZATION: kustomization("resources:\n- file:///srv/git/x.git\n")},
        {}, 1, [GIT_URL]),
    "git URL: a local directory named GitHub.com/... (any case)": (
        {KUSTOMIZATION: kustomization("resources:\n- GitHub.com/giantswarm/x\n"),
         **local_base("GitHub.com/giantswarm/x")},
        {}, 1, ["'GitHub.com/giantswarm/x'", GIT_URL]),
    "git URL: a local directory named user@host/... (SCP-style user, another host)": (
        {KUSTOMIZATION: kustomization("resources:\n- bob@git.example.com/org/x\n"),
         **local_base("bob@git.example.com/org/x")},
        {}, 1, [GIT_URL]),
    "git URL: a local directory named user@host:... (SCP style)": (
        {KUSTOMIZATION: kustomization("resources:\n- bob@git.example.com:org/x\n"),
         **local_base("bob@git.example.com:org/x")},
        {}, 1, [GIT_URL]),
    "git URL: a local directory named GIT::GitHub.com/... (prefix in another case)": (
        {KUSTOMIZATION: kustomization("resources:\n- GIT::GitHub.com/giantswarm/x\n"),
         **local_base("GIT::GitHub.com/giantswarm/x")},
        {}, 1, [GIT_URL]),
    "HTTP URL: http://": (
        {KUSTOMIZATION: kustomization("resources:\n- http://example.com/manifests.yaml\n")},
        {}, 1, [HTTP_URL]),
    "HTTP URL: a local file named HTTPS:... (Go url.Parse reads the scheme)": (
        {KUSTOMIZATION: kustomization("resources:\n- HTTPS:manifests.yaml\n"),
         f"{ORG}/HTTPS:manifests.yaml": "kind: ConfigMap\n"},
        {}, 1, [HTTP_URL]),
    "git+ssh:// (kustomize reads it as a local path; refused anyway)": (
        {KUSTOMIZATION: kustomization("resources:\n- git+ssh://git@github.com/giantswarm/x\n")},
        {}, 1, [CHARACTER, ALLOWED]),
    "gh: shorthand in a local directory (not a git URL in kustomize v5.7.1; refused anyway)": (
        {KUSTOMIZATION: kustomization("resources:\n- gh:giantswarm/x\n"), **local_base("gh:giantswarm/x")},
        {}, 1, [CHARACTER]),
    "s3:: go-getter prefix": (
        {KUSTOMIZATION: kustomization("resources:\n- s3::https://bucket.example.com/x.yaml\n")},
        {}, 1, [CHARACTER]),
}

PATH_CASES = {
    "./a/../../x is refused by its '..' segment": (
        {KUSTOMIZATION: kustomization("resources:\n- ./patches/../../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, ["'..' segment", ALLOWED]),
    "URL-encoded dots in a local directory": (
        {KUSTOMIZATION: kustomization("resources:\n- '%2e%2e/beta/x.yaml'\n"),
         f"{ORG}/%2e%2e/beta/x.yaml": "kind: ConfigMap\n"},
        {}, 1, [CHARACTER]),
    "a Windows-style path with '..'": (
        {KUSTOMIZATION: kustomization("resources:\n- '..\\beta\\tenant-credential-y-secret.enc.yaml'\n")},
        {}, 1, [CHARACTER]),
    "a Windows-style path that is a local file": (
        {KUSTOMIZATION: kustomization("resources:\n- 'patches\\modelconfig.yaml'\n"),
         f"{ORG}/patches\\modelconfig.yaml": "kind: ModelConfig\n"},
        {}, 1, [CHARACTER]),
    "a Windows drive": (
        {KUSTOMIZATION: kustomization("resources:\n- 'C:\\x.yaml'\n")},
        {}, 1, [CHARACTER]),
    "an empty entry": (
        {KUSTOMIZATION: kustomization("resources:\n- ''\n")},
        {}, 1, ["resources '': not a path", ALLOWED]),
    "a null entry": (
        {KUSTOMIZATION: kustomization("resources:\n-\n")},
        {}, 1, ["resources None: not a path"]),
    "a number entry": (
        {KUSTOMIZATION: kustomization("resources:\n- 1\n")},
        {}, 1, ["resources 1: not a path"]),
    "a mapping entry": (
        {KUSTOMIZATION: kustomization("resources:\n- path: ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, ["not a path"]),
    "an anchor hides the entry in metadata": (
        {KUSTOMIZATION: kustomization("""\
            metadata:
              annotations:
                note: &escape ../beta/tenant-credential-y-secret.enc.yaml
            resources:
            - *escape
            """)},
        {}, 1, ["'../beta/tenant-credential-y-secret.enc.yaml'", "'..' segment"]),
    "a merge key brings in resources": (
        {KUSTOMIZATION: kustomization("""\
            metadata:
              name: x
            <<: {resources: [../beta/tenant-credential-y-secret.enc.yaml]}
            """)},
        {}, 1, [KUSTOMIZATION, "does not parse"]),
    "several YAML documents in one file": (
        {KUSTOMIZATION: kustomization("resources:\n- modelconfig-claude.yaml\n---\n"
                                      "resources:\n- ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, [KUSTOMIZATION, "does not parse"]),
    "kustomization.yml is inspected": (
        {f"{ORG}/kustomization.yml": kustomization("resources:\n- ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, [f"{ORG}/kustomization.yml", "'..' segment"]),
    "Kustomization is inspected": (
        {f"{ORG}/Kustomization": kustomization("resources:\n- ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, [f"{ORG}/Kustomization", "'..' segment"]),
    "a nested kustomization is inspected": (
        {KUSTOMIZATION: kustomization("resources:\n- patches\n"),
         f"{ORG}/patches/kustomization.yaml":
            kustomization("resources:\n- ../../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, [f"{ORG}/patches/kustomization.yaml", "'..' segment"]),
    "an entry that does not exist": (
        {KUSTOMIZATION: kustomization("resources:\n- missing.yaml\n")},
        {}, 1, ["'missing.yaml': does not exist in the kustomization's directory", ALLOWED]),
    "resources that is not a list": (
        {KUSTOMIZATION: kustomization("resources: ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, ["not a list", ALLOWED]),
    "the kustomization's own directory": (
        {KUSTOMIZATION: kustomization("resources:\n- ./\n")},
        {}, 1, ["the kustomization's own directory"]),
    "a directory named like a kustomization file": (
        {f"{ORG}/kustomization.yml/x.yaml": "kind: ConfigMap\n"},
        {}, 1, [f"{ORG}/kustomization.yml: the file itself: cannot be read"]),
    "a key in metadata that kustomize does not know": (
        {KUSTOMIZATION: kustomization("metadata:\n  name: x\n  resources: [../beta]\n")},
        {}, 1, ["metadata.resources: not allowed: metadata may carry only name, namespace, labels and annotations"]),
    "metadata that is not a mapping": (
        {KUSTOMIZATION: kustomization("metadata: [x]\n")},
        {}, 1, ["metadata ['x']: not a mapping"]),
    "a YAML directive": (
        {KUSTOMIZATION: "%YAML 1.2\n---\n" + kustomization("resources:\n- modelconfig-claude.yaml\n")},
        {}, 1, [KUSTOMIZATION, "a YAML directive ('%') is not allowed"]),
    "a plain manifest is not inspected": (
        {KUSTOMIZATION: kustomization("resources:\n- modelconfig-claude.yaml\n"),
         f"{ORG}/configmap.yaml": "kind: ConfigMap\ndata:\n  url: https://example.com/x.yaml\n"},
        {}, 0, ["checked 1 kustomization files"]),
    "a directory with its own kustomization passes": (
        {KUSTOMIZATION: kustomization("resources:\n- modelconfig-claude.yaml\n- sub-dir/\n"),
         **local_base("sub-dir")},
        {}, 0, ["checked 2 kustomization files"]),
}

# Every kustomize field that loads a file, each with an entry that reaches another
# organization's ciphertext. All are refused by name, whatever they list.
FIELD_CASES = {
    f"{field} is refused": (
        {KUSTOMIZATION: kustomization(f"resources:\n- modelconfig-claude.yaml\n{body}")},
        {}, 1, [f"{KUSTOMIZATION}: {field}: not allowed in an organization's kustomization", FIELDS_ALLOWED])
    for field, body in {
        "bases": "bases:\n- github.com/giantswarm/x//deploy?ref=v1\n",
        "components": "components:\n- ../beta\n",
        "patches": "patches:\n- path: ../beta/tenant-credential-y-secret.enc.yaml\n",
        "patchesStrategicMerge": "patchesStrategicMerge:\n- ../beta/tenant-credential-y-secret.enc.yaml\n",
        "patchesJson6902": "patchesJson6902:\n- target: {kind: Secret, name: x}\n"
                           "  path: ../beta/tenant-credential-y-secret.enc.yaml\n",
        "configMapGenerator": "configMapGenerator:\n- name: x\n  files:\n  - ../beta/tenant-credential-y-secret.enc.yaml\n"
                              "  envs:\n  - https://example.com/x.env\n",
        "secretGenerator": "secretGenerator:\n- name: x\n  files:\n  - /etc/passwd\n"
                           "  envs:\n  - ../beta/x.env\n",
        "generators": "generators:\n- |-\n  apiVersion: example.com/v1\n  kind: Exec\n"
                      "  metadata:\n    name: x\n    annotations:\n"
                      "      config.kubernetes.io/function: |\n        exec:\n          path: /bin/sh\n",
        "transformers": "transformers:\n- ../beta/transformer.yaml\n",
        "validators": "validators:\n- https://example.com/validator.yaml\n",
        "crds": "crds:\n- https://example.com/crd.yaml\n",
        "configurations": "configurations:\n- ../beta/configuration.yaml\n",
        "replacements": "replacements:\n- path: ../beta/replacement.yaml\n",
        "helmCharts": "helmCharts:\n- name: x\n  repo: https://charts.example.com\n",
        "helmGlobals": "helmGlobals:\n  chartHome: ../beta\n",
        "openapi": "openapi:\n  path: https://example.com/schema.json\n",
        "sortOptions": "sortOptions:\n  order: legacy\n",
        "buildMetadata": "buildMetadata: [originAnnotations]\n",
    }.items()
}

# The four classes of giantswarm/giantswarm#39013, one fixture each that must fail.
CLASS_CASES = {
    "class 1, '..': another organization's ciphertext (the acceptance criterion)": (
        {KUSTOMIZATION: kustomization("resources:\n- ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, [KUSTOMIZATION, "resources '../beta/tenant-credential-y-secret.enc.yaml'", "'..' segment"]),
    "class 2, absolute path": (
        {KUSTOMIZATION: kustomization("resources:\n- /etc/passwd\n")},
        {}, 1, [KUSTOMIZATION, "resources '/etc/passwd'", "absolute path"]),
    "class 3, remote git base": (
        {KUSTOMIZATION: kustomization("resources:\n- github.com/giantswarm/x//deploy?ref=v1\n")},
        {}, 1, [KUSTOMIZATION, "resources 'github.com/giantswarm/x//deploy?ref=v1'", GIT_URL]),
    "class 4, plain web URL to a file": (
        {KUSTOMIZATION: kustomization("resources:\n- https://example.com/manifests.yaml\n")},
        {}, 1, [KUSTOMIZATION, "resources 'https://example.com/manifests.yaml'", HTTP_URL]),
    "class 4, plain web URL with an uppercase scheme": (
        {KUSTOMIZATION: kustomization("resources:\n- HTTPS://example.com/manifests.yaml\n")},
        {}, 1, ["resources 'HTTPS://example.com/manifests.yaml'", HTTP_URL]),
    "class 4, plain web URL with a mixed-case http scheme": (
        {KUSTOMIZATION: kustomization("resources:\n- Http://example.com/manifests.yaml\n")},
        {}, 1, ["resources 'Http://example.com/manifests.yaml'", HTTP_URL]),
}

# The paths as agent-manager writes them (agent-manager internal/api/organizations_commit_test.go,
# gitops-commit layout/kustomization.go): objects/ lists one directory per parent, the parent's
# directory lists the organization files, and an organization's content lists its objects, its
# encrypted Secret and a subdirectory with its own kustomization.yaml. A customer installation adds
# admins/ (the installation runbook, step 7.1).
NEW_KUSTOMIZATION = "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n"
PAYMENTS = f"{ORGS}/content/org-acme/payments"
AGENT_MANAGER_LAYOUT = {
    f"{ORGS}/objects/kustomization.yaml": NEW_KUSTOMIZATION + "resources:\n  - org-acme\n",
    f"{ORGS}/objects/org-acme/kustomization.yaml": NEW_KUSTOMIZATION + "resources:\n  - payments.yaml\n",
    f"{ORGS}/objects/org-acme/payments.yaml": "kind: AgentPlatformOrganization\n",
    f"{PAYMENTS}/kustomization.yaml": NEW_KUSTOMIZATION + (
        "resources:\n  - modelconfig-claude.yaml\n  - rolebinding-organization-admins.yaml\n"
        "  - tenant-credential-claude-secret.enc.yaml\n  - agents\n"),
    f"{PAYMENTS}/modelconfig-claude.yaml": "kind: ModelConfig\n",
    f"{PAYMENTS}/rolebinding-organization-admins.yaml": "kind: RoleBinding\n",
    f"{PAYMENTS}/tenant-credential-claude-secret.enc.yaml": "kind: Secret\nsops: {}\n",
    f"{PAYMENTS}/agents/kustomization.yaml": "resources:\n  - sre.yaml\n",
    f"{PAYMENTS}/agents/sre.yaml": "kind: Agent\n",
    f"{ORGS}/admins/kustomization.yaml": NEW_KUSTOMIZATION + "resources:\n  - rolebindings.yaml\n",
    f"{ORGS}/admins/rolebindings.yaml": "kind: RoleBinding\n",
}

# Ways around the check that it must still refuse.
BYPASS_CASES = {
    "a directory listed in resources holds a kustomization with a remote base": (
        {KUSTOMIZATION: kustomization("resources:\n- modelconfig-claude.yaml\n- agents\n"),
         f"{ORG}/agents/kustomization.yaml": kustomization("resources:\n- https://example.com/x.yaml\n")},
        {}, 1, [f"{ORG}/agents/kustomization.yaml", HTTP_URL]),
    "a nested kustomization.yml two levels down": (
        {KUSTOMIZATION: kustomization("resources:\n- a\n"),
         f"{ORG}/a/kustomization.yaml": kustomization("resources:\n- b\n"),
         f"{ORG}/a/b/kustomization.yml": kustomization("resources:\n- ../../../beta\n")},
        {}, 1, [f"{ORG}/a/b/kustomization.yml", "'..' segment"]),
    "a kustomization in JSON": (
        {KUSTOMIZATION: '{"resources": ["../beta/tenant-credential-y-secret.enc.yaml"]}\n'},
        {}, 1, [KUSTOMIZATION, "'..' segment"]),
    "a kustomization with a byte order mark": (
        {KUSTOMIZATION: "﻿" + kustomization("resources:\n- ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, [KUSTOMIZATION, "'..' segment"]),
    "a YAML tag that PyYAML's safe loader does not know": (
        {KUSTOMIZATION: kustomization("resources:\n- !include ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, [KUSTOMIZATION, "does not parse"]),
    "a binary entry": (
        {KUSTOMIZATION: kustomization("resources:\n- !!binary Li4vYmV0YQ==\n")},
        {}, 1, ["not a path"]),
    "the same key twice (the decoders may keep different ones)": (
        {KUSTOMIZATION: kustomization("resources:\n- modelconfig-claude.yaml\n"
                                      "resources:\n- ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, [KUSTOMIZATION, "given twice"]),
    "a field name with a Unicode letter that Go's case folding maps to ASCII": (
        {KUSTOMIZATION: kustomization("reſources:\n- ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, ["not allowed in an organization's kustomization"]),
    "an installation's directory is a symbolic link": (
        {"management-clusters/gazelle/extras/agent-platform-organizations/content/team-a/alpha/kustomization.yaml":
            kustomization("resources:\n- x.yaml\n"),
         "management-clusters/gazelle/extras/agent-platform-organizations/content/team-a/alpha/x.yaml":
            "kind: ConfigMap\n"},
        {"management-clusters/evil": "gazelle"},
        1, ["management-clusters/evil: the directory itself: symbolic link on the path of "
            "management-clusters/evil/extras/agent-platform-organizations"]),
}

# name: (files, symlinks {link: target}, exit code, substrings of the output)
CASES = {
    **CLASS_CASES,
    **REMOTE_CASES,
    **PATH_CASES,
    **FIELD_CASES,
    **BYPASS_CASES,
    "clean: the paths as agent-manager writes them pass": (
        AGENT_MANAGER_LAYOUT, {}, 0, ["checked 5 kustomization files"]),
    "a builtin transformer reads another organization's file": (
        {KUSTOMIZATION: kustomization("resources:\n- modelconfig-claude.yaml\ntransformers:\n- patch.yaml\n"),
         f"{ORG}/patch.yaml": textwrap.dedent("""\
            apiVersion: builtin
            kind: PatchTransformer
            metadata:
              name: copy
            path: ../beta/tenant-credential-y-secret.enc.yaml
            """)},
        {}, 1, [f"{KUSTOMIZATION}: transformers: not allowed in an organization's kustomization"]),
    "a generator is refused": (
        {KUSTOMIZATION: kustomization("""\
            secretGenerator:
            - name: copy
              files:
              - tenant-credential-x-secret.enc.yaml
            """)},
        {}, 1, ["secretGenerator: not allowed in an organization's kustomization"]),
    "a patch is refused": (
        {KUSTOMIZATION: kustomization("resources:\n- modelconfig-claude.yaml\npatches:\n- path: patches/modelconfig.yaml\n")},
        {}, 1, ["patches: not allowed in an organization's kustomization"]),
    "a field in another case (kustomize matches it without case)": (
        {KUSTOMIZATION: kustomization("Resources:\n- ../beta/tenant-credential-y-secret.enc.yaml\n")},
        {}, 1, ["Resources: not allowed in an organization's kustomization"]),
    "listed file is a symbolic link": (
        {KUSTOMIZATION: kustomization("resources:\n- borrowed.yaml\n")},
        {f"{ORG}/borrowed.yaml": "../beta/tenant-credential-y-secret.enc.yaml"},
        1, ["borrowed.yaml", "symbolic link"]),
    "a directory that is a symbolic link": (
        {KUSTOMIZATION: kustomization("resources:\n- modelconfig-claude.yaml\n")},
        {f"{ORG}/borrowed": "../beta"},
        1, [f"{ORG}/borrowed: the file itself: symbolic link in an organization path"]),
    "kustomization file is a symbolic link": (
        {f"{OTHER}/kustomization.yaml": kustomization("resources:\n- tenant-credential-y-secret.enc.yaml\n")},
        {KUSTOMIZATION: "../beta/kustomization.yaml"},
        1, [KUSTOMIZATION, "symbolic link"]),
    "kustomization file does not parse": (
        {KUSTOMIZATION: "resources: [unclosed\n"},
        {}, 1, [KUSTOMIZATION, "does not parse"]),
    "objects/ is in scope": (
        {f"{ORGS}/objects/kustomization.yaml": kustomization("resources:\n- ../content/team-a/alpha\n")},
        {}, 1, [f"{ORGS}/objects/kustomization.yaml", "'..' segment"]),
    "several resources pass": (
        {KUSTOMIZATION: kustomization("""\
            resources:
            - modelconfig-claude.yaml
            - tenant-credential-x-secret.enc.yaml
            """)},
        {}, 0, ["checked 1 kustomization files"]),
    "a file outside the scope is ignored": (
        {"management-clusters/graveler/extras/kustomization.yaml":
            kustomization("resources:\n- ../../../bases/flux\n")},
        {}, 0, ["checked 0 kustomization files"]),
}


class CheckOrganizationKustomizations(unittest.TestCase):
    def test_cases(self):
        for name, (files, links, code, expected) in CASES.items():
            with self.subTest(name), tempfile.TemporaryDirectory() as root:
                for rel, content in {**BASE_FILES, **files}.items():
                    os.makedirs(os.path.join(root, os.path.dirname(rel)), exist_ok=True)
                    with open(os.path.join(root, rel), "w") as fh:
                        fh.write(content)
                for rel, target in links.items():
                    os.symlink(target, os.path.join(root, rel))
                out = subprocess.run([sys.executable, SCRIPT, root], capture_output=True, text=True)
                self.assertEqual(out.returncode, code, out.stdout + out.stderr)
                for s in expected:
                    self.assertIn(s, out.stdout)


if __name__ == "__main__":
    unittest.main()
