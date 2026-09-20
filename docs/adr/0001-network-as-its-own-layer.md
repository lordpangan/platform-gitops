# ADR 0001 — Network as its own layer (`XNetwork`), discovered by tag

- **Status:** Accepted
- **Date:** 2026-08-16

## Context

EKS needs a VPC. We can either bundle the VPC inside the `XEKSCluster` Composition,
or make the network its own claim. We already know the network will be **reused**
(Lambda, RDS) and **connected** (Transit Gateway) — so it's a known shared
requirement, not speculation.

## Decision

- **`XNetwork` is its own layer** — its own XRD + Composition + `Workspace` (VPC,
  subnets across AZs, routing). It outlives clusters and is shared by many consumers.
- **`XEKSCluster` does not create a VPC.** It references a network by name
  (`networkRef`), and the EKS `Workspace` **discovers** the VPC/subnets via OpenTofu
  `data` lookups filtered on a tag (`network=<name>`).

## Alternatives considered

- **Bundle the VPC into `XEKSCluster`** — simplest now; rejected. Extracting a
  *live* VPC later is a dangerous state move — OpenTofu can read it as
  destroy-and-recreate, taking down everything in the VPC. Splitting while the
  network is empty is far cheaper, and reuse is coming.
- **Cross-Composition Crossplane references** (EKS reads `XNetwork`'s status for
  IDs) — more Crossplane-native, but couples the two composites and is fiddly in
  v2. Tag-based discovery keeps them fully decoupled and each testable on its own,
  and every future consumer uses the identical lookup.

## Consequences

- **Delete order matters:** destroy the cluster before the network. Documented so
  nobody pulls the network out from under a live cluster.
- Transit Gateway / peering and new consumers (Lambda, RDS) become additions to the
  network layer or new consumers of the same tag — never an edit to the EKS cluster.
- The link is a **tag contract**; renaming the discovery tag is a breaking change.
  The contract was later extended — discovery now also scopes by `tenant` and
  selects subnets by `tier`. See [ADR 0007](./0007-network-topology-and-subnet-discovery-by-tier.md).
