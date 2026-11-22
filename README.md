# platform-gitops

Everything **ArgoCD watches**. This is the single Git repo that describes the
desired state of the platform and the apps running on it. ArgoCD (running in the
[platform-control-plane](../platform-control-plane) management cluster)
reconciles reality toward what's in here.

Folders split "**what things mean**" (templates) from "**what we want to exist**"
(live requests), and the requests split by **owner**:

```
platform-gitops/
  bootstrap/       # the ArgoCD Applications that watch the folders below (platform team)
  definitions/     # XRDs + Compositions — templates for infra AND apps  (platform team)
  infra-requests/  # infra claims: XNetwork, XEKSCluster (real $$)       (platform team)
  app-requests/    # app claims: the WebApp claims                       (developers)
  test/            # the offline `crossplane render` harness
  docs/            # decisions (ADRs)
```

## What lives where

- **`bootstrap/`** — one ArgoCD `Application` per watched folder, ordered by sync
  wave so the platform API is established before any claim references it. ArgoCD
  is pointed at this folder by a seed `Application` applied from the control-plane
  repo; see [ADR 0007](../platform-control-plane/docs/adr/0007-gitops-bootstrap-seed.md).
- **`definitions/`** — the platform's API: the reusable XRDs + Compositions, for
  **both** infra (an `XEKSCluster` whose Composition wraps a `provider-opentofu`
  `Workspace`) and apps (`WebApp` → Deployment + Service + HPA + Ingress).
- **`infra-requests/`** — the infra **claims** that spin up real cloud resources
  (VPC, IAM/OIDC, EKS). These are claims against an infra XRD, not raw `Workspace`
  objects — the OpenTofu is hidden inside the Composition. Every change is real
  cloud spend.
- **`app-requests/`** — the thin `WebApp` claims a developer's app is described
  by, laid out as `<namespace>/<kind>/<name>.yaml` so ArgoCD auto-discovers them.

## Front door vs escape hatch

Developers **author through Backstage** — its scaffolder writes files into
`app-requests/` for them. They normally never open this repo. It exists as the
**debugging escape hatch**: when something breaks, they *can* read the real
request and the generated resources. Hide Kubernetes in authoring; expose it in
debugging.

## Rendering & tests (development)

The `definitions/` are checked offline with **`crossplane render`** — no cluster,
no AWS, $0. It runs each composition function as a local container, so you need a
Docker daemon (Docker Desktop, or `colima start`) plus the shared devbox toolchain.

```sh
make test            # every render test: smoke, XNetwork, XEKSCluster
make render-xnetwork # print the composed Workspace for an XNetwork claim
make render-eks      # print the composed Workspace for an XEKSCluster claim
make help            # list targets
```

Each layer is asserted three ways — the `dev` preset, the `prd` preset, and a
claim that overrides individual fields (which also checks the un-overridden
preset values don't leak). The `crossplane` CLI comes from the shared
[`../devbox.json`](../devbox.json) (`crossplane-cli`, version-pinned).

The harness under `test/` is the single seam every XRD/Composition is asserted
at. See [`test/README.md`](./test/README.md) for how render works, why
`test/functions.yaml` exists, and **what these tests cannot catch** — render
never parses the OpenTofu inside the composed `Workspace`, so HCL errors surface
for the first time at a real apply.

## CI gates

A PR to `main` can merge only when the ruleset on `main` allows it. The ruleset
requires a PR. It must also require each check in this table.

| Gate | Workflow / job | What it stops |
|---|---|---|
| Release label | `composition-release` / `release-label` | A Composition change that would roll pinned claims by surprise |

The render tests (`make test`) do not run in CI. They need Docker. Run them
before you push.

### Release label

Claims pin a Composition by its `release` label. For example,
`infra-requests/atlas/prd/vpc.yaml` pins `release: "0.1.1"` of
`definitions/network/composition.yaml`. The pin uses
`compositionUpdatePolicy: Automatic`. So if a Composition changes and keeps
`0.1.1`, every claim pinned to `0.1.1` moves to the new content. Nobody
approves that move. This gate stops it.

The gate runs `scripts/check-composition-release.sh`. It checks two things.

**1. Each Composition that the PR adds, changes or renames:**

- It must have a release label with three numbers, such as `0.1.1`.
- If its content changed, the label must go up. It can't stay the same.
- The label can never go down, even with no content change.
- Its `metadata.name` can't change. A new name makes a new Composition, and
  the old one is lost with all its releases (see below).
- A comment or formatting change needs no bump.
- A Composition with no label on `main` takes any valid label as its first.

**2. Each claim that pins a release:**

- A Composition under `definitions/` must serve the claim's `kind`. The check
  matches the claim's `kind` to the Composition's `spec.compositeTypeRef.kind`.
- That Composition must have had the pinned release at some point. The check
  reads the release label from each past commit of the Composition file. It
  does not use git tags.
- A pin to an older release is fine. That is how you roll back.

It does not check:

- Compositions that the PR does not touch. An unlabeled Composition passes
  until a PR changes it.
- Files that git does not track.
- The size of the bump. Major, minor or patch is the reviewer's call
  ([ADR 0010](./docs/adr/0010-xrd-changes-and-api-versions.md)).

The workflow has no `paths:` filter. A required check with a paths filter does
not run on PRs outside those paths. Those PRs then wait for it forever and
can't merge.

Run it before you push:

```sh
make check-release   # this repo against origin/main
make test-release    # the check's own test cases (no Docker)
```

### How a release stays on the cluster

A **revision** is Crossplane's frozen copy of one version of a Composition.
Each time the Composition changes on the cluster, Crossplane makes a new
revision and copies the `release` label onto it. A claim pinned to `0.1.1`
runs the revision that has `release: "0.1.1"`.

Crossplane never deletes old revisions by itself. On our cluster, XNetwork
still has all 9, back to the first one from 2026-09-12. You can see them:

```sh
kubectl get compositionrevisions -l crossplane.io/composition-name=xnetwork
```

Each revision belongs to its Composition. If the Composition is deleted,
Kubernetes deletes all of its revisions too. So old releases are lost only in
these ways:

1. **Someone deletes the Composition file.** ArgoCD would then delete the
   Composition. To stop that, the `platform-definitions` Application does not
   prune (see [`bootstrap/README.md`](./bootstrap/README.md)). The object stays
   on the cluster until someone deletes it by hand. Also, the check fails if a
   claim still uses a kind that no Composition serves.
2. **Someone renames the Composition** (changes `metadata.name`). To ArgoCD,
   that is a new Composition plus an old one to delete. The check fails on a
   rename.
3. **Someone runs `kubectl delete composition ...`.** Nothing in git can stop
   that. Don't do it while a claim pins one of its releases.
4. **The cluster is rebuilt.** ArgoCD applies only the current Composition
   file. So the new cluster has only the current release. All older releases
   are gone, and claims pinned to them stop. Nothing protects against this
   yet. The fix is a planned rebuild step: apply each past release of the
   Composition file in order, oldest first, then the current one. Each apply
   makes one revision with its label, so every release comes back.

### What the release check can't see

The check reads git, not the cluster. It can't see cases 3 and 4 above.

It also can't see one more case: **a commit that never synced.** Say a PR has
two commits. The first sets `0.2.0` and the second sets `0.2.1`. ArgoCD syncs
only the newest commit on `main`, so the cluster never gets a `0.2.0`
revision. The check still counts `0.2.0` as a release, because it is in git.

If a claim pins a release that has no revision, nothing is lost:

- A running claim stays on its current revision. Crossplane does not change
  its `compositionRevisionRef`. A new claim, such as one on a rebuilt cluster,
  composes nothing.
- The claim shows `Synced=False` with the reason
  `cannot fetch Composition: no compatible CompositionRevisions found`, plus a
  warning event.
- Crossplane stops before it composes. The composed `Workspace` and the AWS
  resources stay as they are.
- Crossplane retries. Pin a release that exists, and the claim recovers.

Before you pin back, check that the revision exists:

```sh
kubectl get compositionrevisions -l crossplane.io/composition-name=xnetwork,release=0.1.1
```

## Documentation

Decisions and the alternatives rejected live in [`docs/adr/`](./docs/adr/).
Each folder's README covers how that folder works.

## Status

Phase 2 (the platform API) — see [`../ROADMAP.md`](../ROADMAP.md).
`definitions/` serves `XNetwork` and `XEKSCluster`; ArgoCD reconciles this repo
via `bootstrap/`; the first infra claims are live in `infra-requests/`.
`app-requests/` stays a placeholder until Phase 5.
