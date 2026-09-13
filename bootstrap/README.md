# bootstrap/

The ArgoCD `Application` objects that tell ArgoCD which folders in this repo to
watch. One Application per folder.

## Where the parent is

These are *child* Applications. The parent — the root `Application` that points
ArgoCD at this folder in the first place — is **not in this repo**. It is applied
by the `argocd` Ansible role in
[platform-control-plane](../../platform-control-plane).

That seam is deliberate. You cannot put "here is the GitOps repo" inside the
GitOps repo, because nothing would ever read it. Something has to point ArgoCD
here once, from outside. Everything after that point is committed here and
reconciled by ArgoCD itself. See
[ADR 0007](../../platform-control-plane/docs/adr/0007-gitops-bootstrap-seed.md).

## The files

| File | Watches | Wave |
|------|---------|------|
| `definitions.yaml` | [`../definitions/`](../definitions/) | 0 |
| `infra-requests.yaml` | [`../infra-requests/`](../infra-requests/) | 1 |

`definitions/` goes first because it installs the XRDs. A claim in
`infra-requests/` refers to a kind like `XNetwork`, and that kind does not exist
until its XRD is established.

## Three settings that matter

**`directory.recurse: true` is required.** The manifests are in subfolders
(`definitions/eks/`, `definitions/network/`), and ArgoCD does not look in
subfolders by default. Without it, ArgoCD finds no manifests, desired state is
empty, actual state matches it, and the Application reports **Synced and
Healthy while applying nothing**. The tell is an empty `status.resources`.

**`prune: true` deletes real infrastructure.** Remove a claim file from
`infra-requests/`, and ArgoCD deletes the claim, which deletes its `Workspace`,
which runs `tofu destroy`. That is how teardown is meant to work here. It is also
how an accidental `git rm` becomes an outage.

**`selfHeal: true` reverts manual changes.** Editing one of these objects with
`kubectl` will not stick. Change the file and push.

## A caveat about waves

Sync waves order the *apply*. They do not wait for cloud resources to exist.

ArgoCD has no health check registered for custom kinds like `XNetwork`, so it
marks them Healthy the moment they are applied. The next wave then starts, even
though the VPC may still be building. Crossplane retries until things converge,
so this is noisy rather than broken — but expect errors in the logs on a cold
build.
