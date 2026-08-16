# Render-test harness for the platform-gitops definitions.
# Uses the shared platform-engineer devbox (crossplane CLI) + colima/Docker.
# `crossplane render` runs composition functions as local containers — offline, $0.

# Point render at whatever Docker endpoint the active context uses (colima or
# Docker Desktop); render otherwise defaults to /var/run/docker.sock.
DOCKER_HOST ?= $(shell docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
export DOCKER_HOST

# The shared devbox.json is one directory up (platform-engineer). devbox only
# reads the config in its own dir, and its --config flag mishandles `--` args, so
# we cd up to run the crossplane binary and pass absolute paths ($(CURDIR)/...).
CROSSPLANE := cd .. && devbox run -- crossplane
FUNCS      := $(CURDIR)/test/functions.yaml

XNETWORK_XR   := $(CURDIR)/test/xnetwork/xr.yaml
XNETWORK_COMP := $(CURDIR)/definitions/network/composition.yaml

.DEFAULT_GOAL := help
.PHONY: help test render-smoke test-smoke render-xnetwork test-xnetwork

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

render-smoke:  ## Render the harness smoke composite (prints composed output)
	@$(CROSSPLANE) render $(CURDIR)/test/smoke/xr.yaml $(CURDIR)/test/smoke/composition.yaml $(FUNCS)

test-smoke:  ## Prove the render harness works end to end (render + assert)
	@out="$$($(CROSSPLANE) render $(CURDIR)/test/smoke/xr.yaml $(CURDIR)/test/smoke/composition.yaml $(FUNCS) 2>/dev/null)"; \
	if echo "$$out" | grep -q 'go-templating renders for smoke'; then \
	  echo "PASS — harness renders via function-go-templating (offline)"; \
	else \
	  echo "FAIL — expected render output not found:"; echo "$$out"; exit 1; \
	fi

test: test-smoke test-xnetwork  ## Run all render tests

render-xnetwork:  ## Render the example XNetwork claim (prints composed output)
	@$(CROSSPLANE) render $(XNETWORK_XR) $(XNETWORK_COMP) $(FUNCS)

test-xnetwork:  ## Render the XNetwork claim and assert the composed Workspace
	@out="$$($(CROSSPLANE) render $(XNETWORK_XR) $(XNETWORK_COMP) $(FUNCS) 2>/dev/null)"; \
	fail=0; \
	check() { if echo "$$out" | grep -qF "$$1"; then echo "  ok: $$2"; else echo "  FAIL: $$2"; fail=1; fi; }; \
	check 'kind: Workspace'                   'one Workspace emitted'; \
	check 'source: Inline'                    'inline module'; \
	check 'kind: ClusterProviderConfig'       'providerConfigRef is the cluster-scoped config'; \
	check 'name: aws-default'                 'providerConfigRef -> aws-default'; \
	check 'network/terraform.tfstate'         'per-layer backend key (network/)'; \
	check 'ap-southeast-1'                     'region pinned to Singapore (residency)'; \
	check 'terraform-aws-modules/vpc'         'community vpc module referenced'; \
	check 'value: sandbox'                    'network_name = claim name'; \
	check 'value: 10.20.0.0/16'               'cidr passed through'; \
	check 'value: "2"'                        'azCount passed through'; \
	check 'managed-by'                        'mandatory platform tags injected'; \
	if [ $$fail -eq 0 ]; then echo "PASS — XNetwork renders the expected Workspace"; else echo "FAIL — XNetwork render assertions"; exit 1; fi
