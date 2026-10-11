# definitions/

The platform's **API** — the reusable templates (XRDs + Compositions) that turn a
short claim into real resources. This holds definitions for **both** layers:

- **Infra:** an infra XRD (e.g. `XEKSCluster`) + its Composition. The Composition
  wraps a `provider-opentofu` `Workspace` that runs the EKS/VPC OpenTofu. A
  developer/platform-team member requests infra with a tiny claim; the OpenTofu
  is hidden. *(Phase 2)*
- **App:** the `WebApp` XRD + Composition — what fields a developer can set, and
  what a claim turns into (Deployment + Service + HPA + Ingress). *(Phase 5)*

The **live claims** that use these templates live in
[`../infra-requests/`](../infra-requests/) and
[`../app-requests/`](../app-requests/). This folder is "what things mean"; those
folders are "what we actually want to exist."

## Claim identity and state

### Applying a claim is idempotent

Committing the same claim twice, re-syncing it, or letting ArgoCD `selfHeal`
re-apply it does **not** create a second set of resources. Crossplane reconciles
the composed `Workspace` continuously, and OpenTofu compares its state file
against reality, so repeated applies converge on the same resources rather than
stacking them up.

### But identity is bound to the claim's name

Each `Workspace` writes to its own state path:

    <namespace>/<claim name>-<layer>/terraform.tfstate
    dev/dev-vpc-1-network/terraform.tfstate

The namespace comes from `workspace_key_prefix`, which the Composition sets from
the claim at template-render time. The middle segment is the OpenTofu workspace
name, which provider-opentofu derives from the composed `Workspace` resource.

That path *is* the resource's identity. Two consequences:

**Renaming a claim is a destroy-and-recreate, not a rename.** The renamed claim
points at a fresh, empty state path. Meanwhile ArgoCD prunes the old claim
(`prune: true`), which deletes its `Workspace` and runs `tofu destroy` on the old
state. Nothing is left behind, but everything is rebuilt: a new VPC id, a new
cluster endpoint, and roughly twenty minutes of EKS teardown and rebuild.
Anything holding the old ids breaks.

**Treat claim names as immutable.** To replace infrastructure, do it
deliberately and knowingly — not as a side effect of tidying up a filename.

### Changing the state layout is the dangerous edit

Editing `workspace_key_prefix` or `key` in a Composition while claims are live is
worse than a rename. The claims are never deleted, so nothing ever runs
`destroy`; their `Workspace`s simply start pointing at empty state paths and
build a *second* set of resources beside the untracked first set. Those originals
keep running and keep billing with nothing managing them.

If the layout ever has to change, destroy every claim first and re-create them
after, or move the state objects in S3 by hand.

## Changes that replace infrastructure

### Editing a preset changes every XR that uses it

A claim without its own `cidr` (or `azCount`, ...) follows the mode's preset in
the Composition. Compositions use `compositionUpdatePolicy: Automatic`, so a
preset edit reaches **every** such XR at once, the moment ArgoCD syncs it.

Changing the `dev` CIDR preset did exactly that and replaced two live VPCs
halfway (learning record 0009). The VPC module can't change a VPC's CIDR: it
plans a replace, then deadlocks on the attached Internet Gateway until the run
is killed.

**Treat presets as append-only.** Need different values? Add a new mode. Any
Composition edit, even a comment, makes a new CompositionRevision and rolls out
to all XRs. That's harmless only if the rendered output stays the same.

### The API blocks replace-forcing edits on claims

CEL transition rules in each XRD reject updates that would replace or remove
live infrastructure (see [`../infra-requests/README.md`](../infra-requests/README.md)
for the list). They guard the **claim**. They can't guard the presets.

## Backstage forms

Each API folder can hold a `backstage-template.yaml`. ArgoCD skips it; Backstage
loads it. It holds two documents: the create form (`kind: Template`) and the
schema the edit form reads (`kind: API`). The `kind: API` schema is a copy of
the XRD's `spec`. **Change it together with `definition.yaml`.** The edit
template replaces the whole `spec`, so a field missing from the copy is
dropped on the next edit.

`_shared/backstage-template.yaml` is the edit template (`update-claim`) for
every kind. It isn't an API, so it has no XRD next to it. See control-plane
ADR 0010.
