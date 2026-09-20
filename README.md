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

## Documentation

Decisions and the alternatives rejected live in [`docs/adr/`](./docs/adr/).
Each folder's README covers how that folder works.

## Status

Phase 2 (the platform API) — see [`../ROADMAP.md`](../ROADMAP.md).
`definitions/` serves `XNetwork` and `XEKSCluster`; ArgoCD reconciles this repo
via `bootstrap/`; the first infra claims are live in `infra-requests/`.
`app-requests/` stays a placeholder until Phase 5.
