# Architecture Decision Records — platform-gitops

Repo-specific decisions live here. System-wide decisions live in
[platform-control-plane/docs/adr](../../../platform-control-plane/docs/adr/).

| # | Decision | Status |
|---|----------|--------|
| [0001](./0001-network-as-its-own-layer.md) | Network as its own layer (`XNetwork`), discovered by tag | Accepted |
| [0002](./0002-region-fixed-singapore-residency.md) | Region fixed to `ap-southeast-1` (Singapore) as a residency guardrail | Accepted |
| [0003](./0003-dev-prd-mode-profiles.md) | `dev`/`prd` mode profiles for `XEKSCluster` | Accepted |
| [0004](./0004-go-templating-composition-function.md) | Go-templating composition function (over patch-and-transform) | Accepted |
| [0005](./0005-claim-identity-namespace-and-state-key.md) | Claims live in tenant namespaces; state keys follow the claim | Accepted |
| [0006](./0006-mode-preset-pattern-for-infra-xrds.md) | Mode presets with per-field overrides as the standard infra XRD shape | Accepted |
| [0007](./0007-network-topology-and-subnet-discovery-by-tier.md) | Network topology by mode, and subnet discovery by tier | Accepted |

> The engine, remote-state, IAM, and GitOps-bootstrap decisions these build on are
> system-wide and live in the
> [control-plane ADRs](../../../platform-control-plane/docs/adr/) (0004–0007).
