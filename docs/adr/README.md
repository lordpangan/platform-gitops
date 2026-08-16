# Architecture Decision Records — platform-gitops

Repo-specific decisions live here. System-wide decisions live in
[platform-control-plane/docs/adr](../../../platform-control-plane/docs/adr/).

| # | Decision | Status |
|---|----------|--------|
| [0001](./0001-network-as-its-own-layer.md) | Network as its own layer (`XNetwork`), discovered by tag | Accepted |
| [0002](./0002-region-fixed-singapore-residency.md) | Region fixed to `ap-southeast-1` (Singapore) as a residency guardrail | Accepted |
| [0003](./0003-dev-prd-mode-profiles.md) | `dev`/`prd` mode profiles for `XEKSCluster` | Accepted |
| [0004](./0004-go-templating-composition-function.md) | Go-templating composition function (over patch-and-transform) | Accepted |

> The engine, remote-state, and IAM decisions these build on are system-wide and
> live in the [control-plane ADRs](../../../platform-control-plane/docs/adr/)
> (0004–0006).
