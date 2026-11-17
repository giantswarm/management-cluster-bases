#!/usr/bin/env python3
"""Refuse an organization's kustomization file that loads anything outside its directory.

In commit mode, agent-manager writes the Agent Platform organizations of an
installation into the installation's management-clusters repository, under
`management-clusters/<mc>/extras/agent-platform-organizations/`: `objects/` (the
AgentPlatformOrganization objects) and `content/<parent>/<name>/` (an
organization's objects and encrypted Secrets, applied by the organization's own
Flux Kustomization). A customer installation may add `admins/`. Every
organization path is decrypted with the installation's one SOPS key, and
kustomize applies what a kustomization file lists. An entry such as
`../other-org/x-secret.enc.yaml` therefore copies another organization's
credential into this organization's namespace, and neither the operator nor the
admission policies can see it: they pin the Flux Kustomization's path, not the
files it lists. See agent-manager docs/organizations-commit-mode.md and
giantswarm/giantswarm#39013.

Every kustomization file in that scope may carry only `apiVersion`, `kind`,
`metadata` and `resources`, and every `resources` entry must be a file or
directory that exists inside the file's own directory: a relative path of
letters, digits, `.`, `_`, `-` and `/`, with no `..` segment, no empty segment
and no symbolic link, that kustomize does not read as a git or HTTP URL.
agent-manager writes only resources there (`<kind>-<object>.yaml`,
`<secret>-secret.enc.yaml`, a subdirectory with its own kustomization file), and
the operator's Flux Kustomization needs nothing else, so nothing legitimate is
lost.

Why an allowlist of fields, not a check of the paths in every field: many
kustomize fields name a file whose content kustomize then reads as
configuration, and that file can name paths of its own. A `transformers:` entry
can be a builtin PatchTransformer with `path: ../beta/x-secret.enc.yaml`; a
generator, a component or a patch file can do the same. Flux's
kustomize-controller allows builtin plugins and local files, so a check that
only sees the first level of paths can be bypassed one file deeper. Only
`resources` entries are applied as objects and never read as configuration, so
only they are allowed, and their paths are checked. kustomize also matches field
names without case (`Resources:` is `resources:`), so only the exact names pass.
Every other field is refused by name: among them the ones that load something,
`bases`, `components`, `patches`, `patchesStrategicMerge`, `patchesJson6902`,
`configMapGenerator`, `secretGenerator`, `generators`, `transformers`,
`validators`, `crds`, `configurations`, `replacements`, `helmCharts`,
`helmGlobals` and `openapi`.

Why a URL rule as well as the existence check: kustomize reads a `resources`
entry as a file first and, if that fails, as a new root; and a new root that
parses as a git URL is cloned before the local directory is looked at. A
directory named `GitHub.com/org/repo` or `bob@host/org/repo` in the
organization's path therefore passes an existence check, and kustomize clones
the repository instead. A plain `http://` or `https://` file URL is downloaded,
and kustomize-controller's `--no-remote-bases` does not stop that. git_url() and
http_url() mirror kustomize's own rules at the version kustomize-controller
v1.7.3 builds with (sigs.k8s.io/kustomize/api v0.20.1):
internal/git/repospec.go extractHost and internal/loader/fileloader.go
IsRemoteFile. The character rule refuses the rest: other schemes, go-getter
prefixes, `%` escapes, backslashes and spaces.

Out of scope: plain manifests (files that are not named like a kustomization
file). The check is about what the build loads, not about the objects it
applies. Every file named `kustomization.yaml`, `kustomization.yml` or
`Kustomization` anywhere under the scope is inspected.

Usage: check-organization-kustomizations.py [repository root]   (default: .)
"""
import glob
import os
import re
import sys

import yaml

SCOPE = "management-clusters/*/extras/agent-platform-organizations"
KUSTOMIZATION_NAMES = ("kustomization.yaml", "kustomization.yml", "Kustomization")

# A `resources` entry may use only these characters.
PATH_CHARACTERS = re.compile(r"[A-Za-z0-9._/-]+")

# sigs.k8s.io/kustomize/api v0.20.1 internal/git/repospec.go extractHost (L252-L287):
# an optional "git::" prefix (L295-L303), then a scheme (L332-L344), or no scheme and an
# SCP-style user (L346-L353), or no scheme and a standard GitHub host (L355-L359). All
# prefixes match without case. Every entry that this matches is refused; kustomize's
# later steps (the host and the repository path) only refuse more.
GIT_PREFIX = re.compile(r"(?i:git::)?(?:(?i:ssh|https|http|file)://|[a-zA-Z][a-zA-Z0-9-]*@|(?i:github\.com)[/:])")
# Go's net/url getScheme, as used by internal/loader/fileloader.go IsRemoteFile (L21-L26):
# a scheme is a letter, then letters, digits, '+', '-' or '.', then ':'. url.Parse
# lowercases it; "http" and "https" are downloaded.
URL_SCHEME = re.compile(r"([A-Za-z][A-Za-z0-9+.-]*):")


def git_url(value):
    """Return whether kustomize v5.7.1 reads `value` as a git repository URL."""
    return GIT_PREFIX.match(value) is not None


def http_url(value):
    """Return whether kustomize v5.7.1 reads `value` as an HTTP(S) file URL."""
    m = URL_SCHEME.match(value)
    return m is not None and m.group(1).lower() in ("http", "https")


class UniqueKeyLoader(yaml.SafeLoader):
    """A safe loader that refuses a key given twice in one mapping.

    PyYAML keeps the last of two equal keys; kustomize's decoder may keep the
    other, so the check would read a list that kustomize does not apply.
    """

    def construct_mapping(self, node, deep=False):
        seen = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in seen:
                raise ValueError(f"key {key!r} given twice")
            seen.add(key)
        return super().construct_mapping(node, deep=deep)


ALLOWED_FIELDS = ("apiVersion", "kind", "metadata", "resources")
FIELD_REFUSAL = ("not allowed in an organization's kustomization: only apiVersion, kind, metadata and "
                 "resources are allowed, and only resources are applied there")
# kustomize's types.ObjectMeta (sigs.k8s.io/kustomize/api v0.20.1 types/objectmeta.go) has only
# these fields; another key fails the build (types/kustomization.go L340-L357).
METADATA_FIELDS = ("name", "namespace", "labels", "annotations")
METADATA_REFUSAL = "not allowed: metadata may carry only name, namespace, labels and annotations"
ENTRY_ALLOWED = ("allowed: a relative path to a file or directory inside this directory, of letters, "
                 "digits, '.', '_', '-' and '/'")


def entries(doc):
    """Yield (field, value, refusal) for the kustomization's fields and resources.

    refusal is a reason when the field is already refused, or None for a
    `resources` entry whose path refusal() checks.
    """
    for key in doc:
        if key not in ALLOWED_FIELDS:
            yield key, None, FIELD_REFUSAL
    metadata = doc.get("metadata")
    if metadata is not None and not isinstance(metadata, dict):
        yield "metadata", metadata, "not a mapping"
    for key in metadata if isinstance(metadata, dict) else ():
        if key not in METADATA_FIELDS:
            yield f"metadata.{key}", None, METADATA_REFUSAL
    values = doc.get("resources") or []
    if not isinstance(values, list):
        yield "resources", values, f"not a list; {ENTRY_ALLOWED}"
        return
    for v in values:
        yield "resources", v, None


def refusal(base, value):
    """Return why `value`, listed in directory `base`, is refused, or None."""
    if not isinstance(value, str) or not value:
        return "not a path"
    if "\n" in value:
        return "inline content is not a path"
    # kustomize tries the HTTP download first and the git clone if that fails
    # (internal/target/kusttarget.go L421-L426).
    remote = []
    if http_url(value):
        remote.append("kustomize reads it as an HTTP URL and downloads it")
    if git_url(value):
        remote.append("kustomize reads it as a git repository URL and clones it")
    if remote:
        return "; if that fails, ".join(remote)
    if value.startswith("/"):
        return "absolute path"
    if not PATH_CHARACTERS.fullmatch(value):
        return "a character other than a letter, a digit, '.', '_', '-' or '/'"
    if "//" in value:
        return "empty path segment ('//' separates a repository from its path in a git URL)"
    if ".." in value.split("/"):
        return "'..' segment"
    # Defence in depth: after the rules above, no entry can normalize outside `base`
    # or resolve outside it through a link that the loop below does not see.
    norm = os.path.normpath(os.path.join(base, value))
    if norm == base:
        return "the kustomization's own directory"
    if os.path.commonpath([base, norm]) != base:
        return "outside the kustomization's directory"
    parts = os.path.relpath(norm, base).split(os.sep)
    for i in range(1, len(parts) + 1):
        if os.path.islink(os.path.join(base, *parts[:i])):
            return "symbolic link"
    if not os.path.exists(norm):
        return "does not exist in the kustomization's directory"
    real_base = os.path.realpath(base)
    if os.path.commonpath([real_base, os.path.realpath(norm)]) != real_base:
        return "outside the kustomization's directory"
    return None


def check_file(path):
    """Return the failure lines of one kustomization file."""
    if os.path.islink(path):
        return [f"{path}: the file itself: symbolic link"]
    try:
        with open(path) as fh:
            text = fh.read()
        # go-yaml v2, which kustomize decodes with, refuses `%YAML 1.2`; PyYAML reads it.
        if any(line.startswith("%") for line in text.splitlines()):
            return [f"{path}: the file itself: a YAML directive ('%') is not allowed"]
        doc = yaml.load(text, Loader=UniqueKeyLoader)
    except (yaml.YAMLError, ValueError, TypeError) as e:
        reason = str(e).replace("\n", " ")
        return [f"{path}: the file itself: does not parse: {reason}"]
    except OSError as e:
        return [f"{path}: the file itself: cannot be read: {e.strerror or e}"]
    if not isinstance(doc, dict):
        return [f"{path}: the file itself: does not parse: not a mapping"]
    base = os.path.dirname(os.path.abspath(path))
    failures = []
    for field, value, reason in entries(doc):
        if reason is not None:
            entry = field if value is None else f"{field} {value!r}"
            failures.append(f"{path}: {entry}: {reason}")
            continue
        reason = refusal(base, value)
        if reason:
            failures.append(f"{path}: {field} {value!r}: {reason}; {ENTRY_ALLOWED}")
    return failures


def scope_link(scope):
    """Return the first symbolic link on the way to `scope`, or None.

    An organization's Flux Kustomization applies its path by name. If
    `management-clusters/<mc>`, its `extras` or the scope itself is a link, that
    name resolves somewhere else, and the files there are not the ones reviewed
    under the name.
    """
    parts = scope.split("/")
    for i in range(1, len(parts) + 1):
        p = "/".join(parts[:i])
        if os.path.islink(p):
            return p
    return None


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    os.chdir(root)
    files, failures = [], []
    for scope in sorted(glob.glob(SCOPE)):
        link = scope_link(scope)
        if link is not None:
            failures.append(f"{link}: the directory itself: symbolic link on the path of {scope}")
            continue
        for dirpath, dirnames, filenames in os.walk(scope):
            dirnames.sort()
            for name in sorted(dirnames + filenames):
                p = os.path.join(dirpath, name)
                if os.path.islink(p) and name not in KUSTOMIZATION_NAMES:
                    failures.append(f"{p}: the file itself: symbolic link in an organization path")
                elif name in KUSTOMIZATION_NAMES:
                    files.append(p)
    for f in files:
        failures.extend(check_file(f))
    for line in failures:
        print(line)
    if failures:
        print(f"{len(failures)} refused entries in {len(files)} kustomization files", file=sys.stderr)
        return 1
    print(f"checked {len(files)} kustomization files under {SCOPE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
