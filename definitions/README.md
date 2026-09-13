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

Each `Workspace` writes to its own state key, derived from the composite at
template-render time:

    <namespace>/<layer>/<name>/terraform.tfstate

That path *is* the resource's identity. Two consequences:

**Renaming a claim is a destroy-and-recreate, not a rename.** The renamed claim
points at a fresh, empty state path. Meanwhile ArgoCD prunes the old claim
(`prune: true`), which deletes its `Workspace` and runs `tofu destroy` on the old
state. Nothing is left behind, but everything is rebuilt: a new VPC id, a new
cluster endpoint, and roughly twenty minutes of EKS teardown and rebuild.
Anything holding the old ids breaks.

**Treat claim names as immutable.** To replace infrastructure, do it
deliberately and knowingly — not as a side effect of tidying up a filename.

### Changing the key scheme is the dangerous edit

Editing the state-key template in a Composition while claims are live is worse
than a rename. The claims are never deleted, so nothing ever runs `destroy`;
their `Workspace`s simply start pointing at empty state paths and build a
*second* set of resources beside the untracked first set. Those originals keep
running and keep billing with nothing managing them.

If the key scheme ever has to change, move the state objects in S3 first, or
destroy every claim before the change and re-create them after.
