# ADR 0005 — Claims live in tenant namespaces, and state keys follow the claim

- **Status:** Accepted
- **Date:** 2026-09-13

## Context

An XRD is a published API. The whole point of offering `XNetwork` is that many
people can file many claims against it.

That raises two questions, and they turn out to be one question:

1. Which namespace does a claim live in?
2. Where does that claim's OpenTofu state file go?

The first version answered both badly. Claims were going into the `argocd`
namespace, and every Composition wrote to a fixed state key:

```hcl
key = "network/terraform.tfstate"
```

With one claim, that works. With two, it does not. The second `XNetwork` claim
would open the first claim's state file, treat the VPC described in it as its
own, and reconcile that VPC to match the new claim. Someone else's network gets
rebuilt or destroyed, and nothing warns you.

## Decision

**Claims live in a namespace owned by whoever owns the workload.** Not `argocd`.

**Each claim gets its own state key, built from the claim's identity:**

```
<namespace>/<layer>/<name>/terraform.tfstate
```

For example: `dev/network/dev-vpc-1/terraform.tfstate`.

The Composition builds it from the composite resource:

```hcl
key = "{{ $xr.metadata.namespace }}/network/{{ $xr.metadata.name }}/terraform.tfstate"
```

OpenTofu does not allow variables in a `backend` block, so this looks illegal at
first glance. It is not. The whole module is a Go template string. Crossplane
renders it before OpenTofu ever sees the file, so by the time OpenTofu parses the
backend, the key is a plain string.

### Why all three segments are needed

**Namespace**, because the namespace is the tenancy boundary. Two teams both
naming their network `dev-vpc-1` is a matter of time, not an edge case.

**Layer**, because Kubernetes lets an `XNetwork` and an `XEKSCluster` share a
name in the same namespace. A Kubernetes object is identified by kind, namespace
*and* name. Drop the kind and the key stops being unique.

**Name**, because that is what distinguishes one claim from the next.

## Alternatives considered

- **One state file per layer** (what we had). Simple, and wrong as soon as a
  second claim exists. Rejected.
- **`<namespace>/<name>`, no layer segment.** Looks sufficient, because claims
  are conventionally named `dev-vpc-1` and `dev-eks`. But nothing enforces that
  convention. A team naming both their network and their cluster after their app
  gets one state file for two different stacks, which is worse than two networks
  colliding. Rejected.
- **Derive the layer from `{{ $xr.kind | lower }}`** instead of writing
  `network` and `eks` by hand. Genuinely better in one way: every Composition
  gets the identical line, so a copy-paste cannot carry a stale prefix. Not
  adopted yet, only because the hand-written version is easier to read while
  there are two layers. Worth revisiting at the third.
- **Key on the resource UID.** Survives renames, which the chosen scheme does
  not. Rejected: the bucket becomes unreadable, and deleting and recreating a
  claim produces a new UID anyway, so it does not really solve renaming.
- **Claims in the `argocd` namespace.** Rejected. That is the GitOps
  controller's own namespace, holding its Applications, its RBAC and its repo
  credentials. Infra claims are tenant content and do not belong there. It also
  throws away the reason Crossplane v2 has namespaced composites: the namespace
  is how you would later separate team A's claims from team B's.

## Consequences

- A claim's name is part of its infrastructure's identity. **Renaming a claim is
  a destroy-and-recreate, not a rename.** The renamed claim points at an empty
  state path, while ArgoCD prunes the old claim and destroys what it built. New
  VPC id, new cluster endpoint, and anything holding the old ids breaks.
- **Changing the key scheme while claims are live is worse than a rename.** The
  claims are never deleted, so nothing runs `destroy`. Their Workspaces just
  start pointing at empty state paths and build a second set of resources beside
  the first. The originals keep running and keep billing, managed by nothing. If
  the scheme must change, move the state objects in S3 first, or destroy every
  claim before the change.
- State locking splits for free. The DynamoDB lock table is shared, but locks are
  taken per state key, so claims no longer block each other.
- Composed `Workspace` objects land in the claim's namespace, so namespace-scoped
  RBAC works on them the way it would for any other workload.
- The user-facing version of all this lives in
  [`../../definitions/README.md`](../../definitions/README.md).
