# platform-gitops

Everything **ArgoCD watches**. This is the single Git repo that describes the
desired state of the platform and the apps running on it. ArgoCD (running in the
[platform-control-plane](../platform-control-plane) management cluster)
reconciles reality toward what's in here.

Folders split "**what things mean**" (templates) from "**what we want to exist**"
(live requests), and the requests split by **owner**:

```
platform-gitops/
  definitions/     # XRDs + Compositions — templates for infra AND apps  (platform team)
  infra-requests/  # infra claims: XEKSCluster etc. (real $$)            (platform team)
  app-requests/    # app claims: the WebApp claims                       (developers)
  docs/            # decisions (ADRs) and journal
```

## What lives where

- **`definitions/`** — the platform's API: the reusable XRDs + Compositions, for
  **both** infra (an `XEKSCluster` whose Composition wraps a `provider-terraform`
  `Workspace`) and apps (`WebApp` → Deployment + Service + HPA + Ingress).
- **`infra-requests/`** — the infra **claims** that spin up real cloud resources
  (VPC, IAM/OIDC, EKS). These are claims against an infra XRD, not raw `Workspace`
  objects — the Terraform is hidden inside the Composition. Every change is real
  cloud spend.
- **`app-requests/`** — the thin `WebApp` claims a developer's app is described
  by, laid out as `<namespace>/<kind>/<name>.yaml` so ArgoCD auto-discovers them.

## Front door vs escape hatch

Developers **author through Backstage** — its scaffolder writes files into
`app-requests/` for them. They normally never open this repo. It exists as the
**debugging escape hatch**: when something breaks, they *can* read the real
request and the generated resources. Hide Kubernetes in authoring; expose it in
debugging.

## Documentation

- **Decisions:** [`docs/adr/`](./docs/adr/)
- **Journal:** [`docs/journal/`](./docs/journal/)

## Status

Phase 0 (set the table) — see [`../ROADMAP.md`](../ROADMAP.md). Folders are
placeholders until later phases fill them in.
