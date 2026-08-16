# ADR 0002 — Region fixed to `ap-southeast-1` (Singapore) as a residency guardrail

- **Status:** Accepted
- **Date:** 2026-08-16

## Context

The platform must keep **all workloads in Singapore** (data-residency requirement).
The question: should `region` be a claim field at all?

## Decision

- **Region is not a claim field** on any infra XRD. The platform injects
  `ap-southeast-1` inside the Compositions, so residency is guaranteed **by
  construction**, not by review.
- It is a platform-owned constant — changeable in one place if a sibling region is
  ever genuinely needed — never a per-request knob.

## Alternatives considered

- **Expose `region` (optional, default SG)** — flexible, but a requester could then
  place workloads outside SG, breaking residency. Rejected: a guardrail beats
  flexibility here.
- **Expose it but enforce SG via policy (Kyverno)** — defence in depth, but
  exposing-then-rejecting is worse UX than simply not exposing. Policy can still be
  added later as a backstop.

## Consequences

- Multi-region becomes a deliberate future change (add the region to platform
  config, likely with a per-region network), not a claim edit.
- One fewer field on every infra claim, and a clean compliance story.
