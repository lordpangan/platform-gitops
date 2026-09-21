# Render-test harness for the platform-gitops definitions.
# Uses the shared platform-engineer devbox (crossplane CLI) + colima/Docker.
# `crossplane render` runs composition functions as local containers — offline, $0.
# It checks the composed *Workspace* (structure), not the OpenTofu HCL; HCL and
# module/provider version compatibility are settled at the first real apply.

# Point render at whatever Docker endpoint the active context uses (colima or
# Docker Desktop); render otherwise defaults to /var/run/docker.sock.
DOCKER_HOST ?= $(shell docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
export DOCKER_HOST

# The shared devbox.json is one directory up (platform-engineer). devbox only
# reads the config in its own dir, and its --config flag mishandles `--` args, so
# we cd up to run the crossplane binary and pass absolute paths ($(CURDIR)/...).
CROSSPLANE := cd .. && devbox run -- crossplane
FUNCS      := $(CURDIR)/test/functions.yaml

XNETWORK_XRD         := $(CURDIR)/definitions/network/definition.yaml
XNETWORK_COMP        := $(CURDIR)/definitions/network/composition.yaml
XNETWORK_XR          := $(CURDIR)/test/xnetwork/xr.yaml
XNETWORK_PRD_XR      := $(CURDIR)/test/xnetwork/xr-prd.yaml
XNETWORK_OVERRIDE_XR := $(CURDIR)/test/xnetwork/xr-override.yaml
EKS_XRD         := $(CURDIR)/definitions/eks/definition.yaml
EKS_COMP        := $(CURDIR)/definitions/eks/composition.yaml
EKS_XR          := $(CURDIR)/test/eks/xr.yaml
EKS_PRD_XR      := $(CURDIR)/test/eks/xr-prd.yaml
EKS_OVERRIDE_XR := $(CURDIR)/test/eks/xr-override.yaml

.DEFAULT_GOAL := help
.PHONY: help test render-smoke test-smoke render-xnetwork test-xnetwork test-xnetwork-prd test-xnetwork-override render-eks test-eks test-eks-prd test-eks-override

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

test: test-smoke test-xnetwork test-xnetwork-prd test-xnetwork-override test-eks test-eks-prd test-eks-override  ## Run all render tests

# --- harness smoke -----------------------------------------------------------

render-smoke:  ## Render the harness smoke composite (prints composed output)
	@$(CROSSPLANE) render $(CURDIR)/test/smoke/xr.yaml $(CURDIR)/test/smoke/composition.yaml $(FUNCS)

test-smoke:  ## Prove the render harness works end to end (render + assert)
	@out="$$($(CROSSPLANE) render $(CURDIR)/test/smoke/xr.yaml $(CURDIR)/test/smoke/composition.yaml $(FUNCS) 2>/dev/null)"; \
	if echo "$$out" | grep -q 'go-templating renders for smoke'; then \
	  echo "PASS — harness renders via function-go-templating (offline)"; \
	else \
	  echo "FAIL — expected render output not found:"; echo "$$out"; exit 1; \
	fi

# --- XNetwork ----------------------------------------------------------------

render-xnetwork:  ## Render the example XNetwork claim (prints composed output)
	@$(CROSSPLANE) render $(XNETWORK_XR) $(XNETWORK_COMP) $(FUNCS) --xrd $(XNETWORK_XRD)

test-xnetwork:  ## Render the XNetwork claim and assert the composed Workspace
	@out="$$($(CROSSPLANE) render $(XNETWORK_XR) $(XNETWORK_COMP) $(FUNCS) --xrd $(XNETWORK_XRD) 2>/dev/null)"; \
	fail=0; \
	check()  { if echo "$$out" | grep -qE "$$1"; then echo "  ok: $$2"; else echo "  FAIL: $$2"; fail=1; fi; }; \
	refute() { if echo "$$out" | grep -qE "$$1"; then echo "  FAIL: $$2"; fail=1; else echo "  ok: $$2"; fi; }; \
	check 'kind: Workspace'             'one Workspace emitted'; \
	check 'source: Inline'             'inline module'; \
	check 'kind: ClusterProviderConfig' 'providerConfigRef is the cluster-scoped config'; \
	check 'name: aws-default'          'providerConfigRef -> aws-default'; \
	check 'workspace_key_prefix += *"platform"' 'backend prefix = claim namespace'; \
	check 'ap-southeast-1'             'region pinned to Singapore (residency)'; \
	check 'terraform-aws-modules/vpc'  'community vpc module referenced'; \
	check 'value: sandbox'             'network_name = claim name'; \
	check 'value: 192.168.0.0/16'        'cidr passed through'; \
	check 'value: "2"'                 'azCount passed through'; \
	check 'managed-by'                 'mandatory platform tags injected'; \
	check '"tenant" += *var.tenant'    'tenant tag = claim namespace'; \
	check '"env" += *var.mode'         'env tag = mode'; \
	check 'public_subnet_tags  = { tier = "public" }'          'tier public_subnet_tags = public'; \
	check 'private_subnet_tags = { tier = "private" }'          'tier private_subnet_tags = private'; \
	check 'value: "false"'             'dev preset: NAT gateway off (cost)'; \
	check 'value: "true"'              'dev preset: map public IP on launch'; \
	refute '<no value>'                'no unresolved template values'; \
	if [ $$fail -eq 0 ]; then echo "PASS — XNetwork renders the expected Workspace"; else echo "FAIL — XNetwork render assertions"; exit 1; fi

test-xnetwork-prd:  ## Render the XNetwork (prd) claim and assert the prd preset
	@out="$$($(CROSSPLANE) render $(XNETWORK_PRD_XR) $(XNETWORK_COMP) $(FUNCS) --xrd $(XNETWORK_XRD) 2>/dev/null)"; \
	fail=0; \
	check()  { if echo "$$out" | grep -qE "$$1"; then echo "  ok: $$2"; else echo "  FAIL: $$2"; fail=1; fi; }; \
	refute() { if echo "$$out" | grep -qE "$$1"; then echo "  FAIL: $$2"; fail=1; else echo "  ok: $$2"; fi; }; \
	check 'value: 172.16.0.0/12' 'prd preset: cidr 172.16.0.0/12'; \
	check 'value: "3"'           'prd preset: azCount 3'; \
	check 'value: "true"'        'prd preset: NAT gateway on'; \
	check 'value: "false"'       'prd preset: map public IP on launch'; \
	refute '<no value>'          'no unresolved template values'; \
	if [ $$fail -eq 0 ]; then echo "PASS — XNetwork (prd) renders the expected preset"; else echo "FAIL — XNetwork prd assertions"; exit 1; fi

test-xnetwork-override:  ## Render an override claim and assert explicit spec.* beat the preset
	@out="$$($(CROSSPLANE) render $(XNETWORK_OVERRIDE_XR) $(XNETWORK_COMP) $(FUNCS) --xrd $(XNETWORK_XRD) 2>/dev/null)"; \
	fail=0; \
	check()  { if echo "$$out" | grep -qE "$$1"; then echo "  ok: $$2"; else echo "  FAIL: $$2"; fail=1; fi; }; \
	refute() { if echo "$$out" | grep -qE "$$1"; then echo "  FAIL: $$2"; fail=1; else echo "  ok: $$2"; fi; }; \
	check 'value: 192.168.0.0/16' 'override wins: cidr'; \
	check 'value: "3"'            'un-set field holds: azCount still prd preset (3)'; \
	check 'value: "true"'         'platform-fixed: NAT stays on for prd (not overridable)'; \
	refute 'value: 172.16.0.0/12' 'cidr preset did not leak (no 172.16.0.0/12)'; \
	refute '<no value>'           'no unresolved template values'; \
	if [ $$fail -eq 0 ]; then echo "PASS — XNetwork override beats preset per-field"; else echo "FAIL — XNetwork override assertions"; exit 1; fi

# --- XEKSCluster -------------------------------------------------------------

render-eks:  ## Render the example XEKSCluster claim (prints composed output)
	@$(CROSSPLANE) render $(EKS_XR) $(EKS_COMP) $(FUNCS) --xrd $(EKS_XRD)

test-eks:  ## Render the XEKSCluster (dev) claim and assert the composed Workspace
	@out="$$($(CROSSPLANE) render $(EKS_XR) $(EKS_COMP) $(FUNCS) --xrd $(EKS_XRD) 2>/dev/null)"; \
	fail=0; \
	check()  { if echo "$$out" | grep -qE "$$1"; then echo "  ok: $$2"; else echo "  FAIL: $$2"; fail=1; fi; }; \
	refute() { if echo "$$out" | grep -qE "$$1"; then echo "  FAIL: $$2"; fail=1; else echo "  ok: $$2"; fi; }; \
	check 'kind: Workspace'                 'one Workspace emitted'; \
	check 'kind: ClusterProviderConfig'     'providerConfigRef is the cluster-scoped config'; \
	check 'name: aws-default'               'providerConfigRef -> aws-default'; \
	check 'workspace_key_prefix += *"platform"' 'backend prefix = claim namespace'; \
	check 'ap-southeast-1'                  'region pinned to Singapore (residency)'; \
	check 'terraform-aws-modules/eks'       'community eks module referenced'; \
	check 'encryption_config += *null'      'no custom KMS key (AWS-managed encryption)'; \
	check 'tag:network'                     'VPC discovered by the network tag'; \
	check 'tag:tenant'                      'VPC discovery scoped to the tenant'; \
	check 'value: SPOT'                     'dev preset: SPOT capacity'; \
	check 'value: t3.small'                 'dev preset: t3.small instance'; \
	check 'value: "2"'                      'dev preset: desired 2'; \
	check 'value: "1.33"'                   'version default (1.33)'; \
	check 'value: sandbox'                  'networkRef passed through'; \
	check '"tenant" += *var.tenant'         'tenant tag = claim namespace'; \
	check '"cluster" += *var.cluster_name'  'cluster identity tag'; \
	check '"env" += *var.mode'              'env tag = mode'; \
	refute '"env" += *var.cluster_name'     'env is not the cluster name (old bug)'; \
	refute '<no value>'                     'no unresolved template values'; \
	if [ $$fail -eq 0 ]; then echo "PASS — XEKSCluster (dev) renders the expected Workspace"; else echo "FAIL — XEKSCluster render assertions"; exit 1; fi

test-eks-prd:  ## Render the XEKSCluster (prd) claim and assert the prd preset
	@out="$$($(CROSSPLANE) render $(EKS_PRD_XR) $(EKS_COMP) $(FUNCS) --xrd $(EKS_XRD) 2>/dev/null)"; \
	fail=0; \
	check()  { if echo "$$out" | grep -qE "$$1"; then echo "  ok: $$2"; else echo "  FAIL: $$2"; fail=1; fi; }; \
	refute() { if echo "$$out" | grep -qE "$$1"; then echo "  FAIL: $$2"; fail=1; else echo "  ok: $$2"; fi; }; \
	check 'value: ON_DEMAND'   'prd preset: ON_DEMAND capacity'; \
	check 'value: t3.medium'   'prd preset: t3.medium instance'; \
	check 'value: "2"'         'prd preset: min 2'; \
	check 'value: "3"'         'prd preset: desired 3'; \
	check 'value: "6"'         'prd preset: max 6'; \
	refute '<no value>'        'no unresolved template values'; \
	if [ $$fail -eq 0 ]; then echo "PASS — XEKSCluster (prd) renders the expected preset"; else echo "FAIL — XEKSCluster prd assertions"; exit 1; fi

test-eks-override:  ## Render an override claim and assert explicit nodes.* beat the preset
	@out="$$($(CROSSPLANE) render $(EKS_OVERRIDE_XR) $(EKS_COMP) $(FUNCS) --xrd $(EKS_XRD) 2>/dev/null)"; \
	fail=0; \
	check()  { if echo "$$out" | grep -qE "$$1"; then echo "  ok: $$2"; else echo "  FAIL: $$2"; fail=1; fi; }; \
	refute() { if echo "$$out" | grep -qE "$$1"; then echo "  FAIL: $$2"; fail=1; else echo "  ok: $$2"; fi; }; \
	check 'value: t3.large'    'override wins: instanceType (t3.large)'; \
	check 'value: ON_DEMAND'   'override wins: capacityType (ON_DEMAND)'; \
	check 'value: "5"'         'override wins: a count (desired 5)'; \
	check 'value: "3"'         'un-set field holds: max still dev preset (3)'; \
	refute 'value: t3.small'   'instance preset did not leak (no t3.small)'; \
	refute 'value: SPOT'       'capacity preset did not leak (no SPOT)'; \
	refute '<no value>'        'no unresolved template values'; \
	if [ $$fail -eq 0 ]; then echo "PASS — XEKSCluster override beats preset per-field"; else echo "FAIL — XEKSCluster override assertions"; exit 1; fi
