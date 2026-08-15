# definitions/

The platform's **API** — the reusable templates (XRDs + Compositions) that turn a
short claim into real resources. This holds definitions for **both** layers:

- **Infra:** an infra XRD (e.g. `XEKSCluster`) + its Composition. The Composition
  wraps a `provider-terraform` `Workspace` that runs the EKS/VPC Terraform. A
  developer/platform-team member requests infra with a tiny claim; the Terraform
  is hidden. *(Phase 2)*
- **App:** the `WebApp` XRD + Composition — what fields a developer can set, and
  what a claim turns into (Deployment + Service + HPA + Ingress). *(Phase 5)*

The **live claims** that use these templates live in
[`../infra-requests/`](../infra-requests/) and
[`../app-requests/`](../app-requests/). This folder is "what things mean"; those
folders are "what we actually want to exist."
