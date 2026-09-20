# ADR 0007 — Network topology by mode, and subnet discovery by tier

- **Status:** Accepted
- **Date:** 2026-09-20

## Context

[ADR 0001](./0001-network-as-its-own-layer.md) chose to discover the network by a
tag: the EKS `Workspace` finds the VPC with a `data` lookup on `network=<name>`.
Building the first real EKS claim showed that one tag is not enough. Two problems
surfaced, both found before any cluster was applied.

**Claim names are not unique across namespaces.** Two tenants can each name a
network `dev-vpc-1`. A lookup on `network=dev-vpc-1` alone then matches both, and
the cluster could attach to another tenant's VPC. This is the same cross-namespace
collision that [ADR 0005](./0005-claim-identity-namespace-and-state-key.md)
handled for state, reappearing in discovery.

**The subnet lookup returned every subnet in the VPC.** The `aws_subnets` data
source filtered on `vpc-id` only, so it handed EKS both the public and the private
subnets. That breaks the `dev` cluster. The `dev` preset runs with NAT off for
cost, so the private subnets have no route to the internet. A node placed there
cannot reach ECR or the EKS API and never joins. Checking the live VPC also showed
the public subnets do not auto-assign public IPs, so even selecting them is not
enough on its own.

So the network layer needed a way to say which subnets are public and which are
private, and the EKS layer needed to pick the right set for the mode.

## Decision

**VPC discovery is scoped by tenant.** The EKS lookup now filters on
`network=<name>` and `tenant=<namespace>` together. The network layer already
stamps both tags. A claim resolves only to a VPC in its own namespace.

**Subnets carry a `tier` tag.** The network Composition tags its subnets
`tier=public` and `tier=private` (via the VPC module's `public_subnet_tags` and
`private_subnet_tags`). This is an explicit contract the platform owns, not a
guess from the subnet name.

**EKS selects subnets by tier, and the tier is chosen by mode.**

- `dev` → `tier=public`
- `prd` → `tier=private`

**Topology is a mode decision, held in the network preset.** The two knobs move
together with the node placement:

| mode | NAT gateway | public subnets auto-assign IP | EKS nodes land in |
|------|-------------|-------------------------------|-------------------|
| `dev` | off | yes (`map_public_ip_on_launch`) | public subnets |
| `prd` | on  | no | private subnets |

The reasoning is a cost-versus-isolation trade. `dev` gives up isolation to avoid
the NAT gateway bill: nodes sit in public subnets and reach the internet through
the internet gateway with a public IP. `prd` pays for NAT and keeps its nodes
private. Both `map_public_ip` and NAT are platform-fixed by mode with no override,
per [ADR 0006](./0006-mode-preset-pattern-for-infra-xrds.md) Rule 3.

## Alternatives considered

- **Run NAT in `dev` too, so nodes are always private.** Uniform and more secure.
  Rejected: a NAT gateway is about USD 32/month plus data, which defeats the point
  of a cheap `dev` preset. A sandbox does not need private nodes.
- **Give `dev` private nodes with VPC endpoints instead of NAT.** No NAT bill,
  nodes stay private. Rejected: several interface endpoints (ECR, STS, EC2, more)
  each cost money and add moving parts. Too much machinery for a sandbox.
- **Select subnets by parsing the `Name` tag.** The VPC module already names
  subnets `<name>-public-<az>`, so a `Name` wildcard would work without a new tag.
  Rejected: it couples us to the module's naming scheme. An explicit `tier` tag is
  a contract we control.
- **Keep `network`-only discovery and rely on unique claim names.** Rejected: the
  cross-namespace collision was reproduced on purpose while testing state (ADR
  0005). Names are not unique, so discovery cannot assume they are.

## Consequences

- **The tag contract from ADR 0001 is now three tags.** `network` and `tenant`
  find the VPC; `tier` finds the subnets. Renaming any of them, or changing the
  mode-to-tier mapping, is a breaking change to every consumer.
- **`dev` nodes have public IPs.** Acceptable for a sandbox, not for anything
  sensitive. If `dev` ever needs isolation, switch it to NAT or endpoints — the
  preset is the one place to change.
- **Adding the tags to a live VPC is safe.** Re-applying the network layer added
  the `tier` tags and flipped `map_public_ip_on_launch` in place. The VPC kept its
  ID, so discovery kept working and nothing downstream was recreated.
- **Every future network consumer uses the same lookup.** Lambda, RDS, and the
  like discover subnets by `tier` the same way EKS does.
