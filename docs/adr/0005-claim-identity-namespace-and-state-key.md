# ADR 0005 — Claims live in tenant namespaces, and state keys follow the claim

- **Status:** Accepted
- **Date:** 2026-09-13

## Context

An XRD is a published API. Many people file many claims against it. Each claim
builds its own resources, so each claim needs its own OpenTofu state file.

At first every Composition wrote to the same key:

```hcl
key = "network/terraform.tfstate"
```

That looks like every claim sharing one state file. They did not. The first real
apply wrote state here:

```
env:/dev-vpc-1-network/network/terraform.tfstate
```

OpenTofu adds a prefix when a run uses a named workspace. The full path is:

```
<workspace_key_prefix>/<workspace name>/<key>
```

`workspace_key_prefix` defaults to `env:`. provider-opentofu creates one OpenTofu
workspace per `Workspace` resource and names it after that resource. So claims
were already kept apart, by a provider behaviour we never chose.

Two problems with leaving it there.

**It hid where state actually lives.** The Composition said
`network/terraform.tfstate`. That was not the path. Reading the file told you the
wrong thing, and the right answer required knowing undocumented provider
behaviour.

**It did not cover every case.** The `Workspace` resource is named after the
claim only:

```yaml
name: {{ $xr.metadata.name }}-network
```

No namespace. So `dev-vpc-1` in namespace `dev` and `dev-vpc-1` in namespace
`team-b` both produce a resource named `dev-vpc-1-network`, and both would land
on `env:/dev-vpc-1-network/network/terraform.tfstate`. One state file, two
claims. Once namespaces are how we separate teams, two teams picking the same
name is normal.

We confirmed this by applying both claims and reading the bucket. The provider's
workspace name was identical for both. Only our key kept them apart.

## Decision

**Claims live in a namespace owned by whoever owns the workload.** Not `argocd`.

**The namespace goes in `workspace_key_prefix`, and the key becomes a constant:**

```hcl
backend "s3" {
  workspace_key_prefix = "{{ $xr.metadata.namespace }}"
  key                  = "terraform.tfstate"
}
```

State then lands at:

```
dev/dev-vpc-1-network/terraform.tfstate
team-b/dev-vpc-1-network/terraform.tfstate
```

Three segments, each stating one fact once:

- **namespace**, from the prefix, which we set
- **claim name and layer**, from the workspace name, which the provider sets
- **the file**, from the key

OpenTofu does not allow variables in a `backend` block, so the template looks
illegal at first glance. It is not. The whole module is a Go template string.
Crossplane renders it before OpenTofu ever sees the file. By then the value is
plain text.

### Why not put the namespace in the key instead

We tried that first:

```hcl
key = "{{ $xr.metadata.namespace }}/network/{{ $xr.metadata.name }}/terraform.tfstate"
```

It worked, but the result read badly, because the provider's prefix is still
there:

```
env:/dev-vpc-1-network/dev/network/dev-vpc-1/terraform.tfstate
```

The claim name appears twice and the layer appears twice. Two naming schemes
stacked on top of each other. Moving the namespace into the prefix removes the
duplication, because the provider's segment already carries claim name and layer.

## Alternatives considered

- **Leave the key as it was.** It happened to work. Rejected: it depends on
  undocumented provider behaviour, it hides where state actually lives, and two
  namespaces sharing a claim name collide.
- **Namespace in the key, prefix left as `env:`.** Correct, and what we shipped
  first. Rejected after seeing the paths: every identifier appeared twice.
- **Name the `Workspace` resource `<namespace>-<name>-<layer>`** so the
  provider's own segment is unique. Rejected: renaming a live managed resource
  destroys and recreates it, and the name gets awkward (`dev-dev-vpc-1-network`).
  It also leaves the layout dependent on provider behaviour rather than on
  something we control.
- **Key on the resource UID.** Survives renames, which this scheme does not.
  Rejected: the bucket becomes unreadable, and deleting and recreating a claim
  gives a new UID anyway, so renaming is not really solved.
- **Claims in the `argocd` namespace.** Rejected. That namespace belongs to the
  GitOps controller and holds its Applications, RBAC and repo credentials. Infra
  claims are tenant content. It also wastes the reason Crossplane v2 has
  namespaced composites: the namespace is how we would separate team A from
  team B later.

## Consequences

- A claim's name is part of its infrastructure's identity. **Renaming a claim is
  a destroy-and-recreate, not a rename.** The renamed claim points at an empty
  state path, and ArgoCD prunes the old claim and destroys what it built. New VPC
  id, new cluster endpoint, and anything holding the old ids breaks.
- **Changing the state layout while claims are live is worse than a rename.** The
  claims are never deleted, so nothing runs `destroy`. Their Workspaces point at
  empty state paths and build a second set of resources beside the first. The
  originals keep running and keep billing, managed by nothing. If the layout must
  change, destroy every claim first, or move the state objects in S3 by hand.
- We hit a mild version of this on the first apply. The claim was committed
  before the key change, so OpenTofu found a cached backend that no longer
  matched and stopped with `Backend configuration changed`. Nothing had been
  built. Restarting the provider pod cleared the cached working directory.
- The layout still depends on the provider naming its workspace after the
  `Workspace` resource. If that ever changes, paths move. The namespace segment
  is ours, so tenant separation survives; claim-level separation would not.
- State locking splits per path. The DynamoDB lock table is shared, but locks are
  taken per state file, so claims do not block each other.
- Composed `Workspace` objects land in the claim's namespace, so namespace-scoped
  RBAC works on them like any other workload.
- Every resource is tagged `tenant = <namespace>`, so the same boundary is
  visible in AWS as well as in the bucket.
- The user-facing version of all this lives in
  [`../../definitions/README.md`](../../definitions/README.md).
