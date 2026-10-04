# kube-gateway-lab - convenience targets. Everything also works without make
# (see README): `sudo ./deploy.sh` is the only command needed for a deployment.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

VENV        := .venv
INVENTORY   ?= ansible/inventory/local.ini
ANSIBLE_ENV := ANSIBLE_CONFIG=ansible/ansible.cfg ANSIBLE_COLLECTIONS_PATH=.ansible/collections PATH=$(CURDIR)/$(VENV)/bin:$$PATH

.PHONY: help deploy verify credentials ca status destroy lint diagnostics dashboard

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deploy: ## Deploy (or converge) the whole lab: kubeadm cluster + platform + app + smoke test
	./deploy.sh

verify: ## Run the end-to-end smoke test (Gateway API, Prometheus, Fluentd/OpenSearch)
	./scripts/smoke-test.sh

credentials: ## Print endpoints and generated credentials
	./scripts/show-access.sh

ca: ## Export the lab root CA to ./lab-ca.crt (for curl --cacert / browser trust)
	kubectl --kubeconfig /etc/kubernetes/admin.conf -n cert-manager get secret lab-root-ca \
	  -o jsonpath='{.data.ca\.crt}' | base64 -d > lab-ca.crt && echo "wrote lab-ca.crt"

status: ## Show the state of nodes, Gateway API objects and workloads
	@export KUBECONFIG=/etc/kubernetes/admin.conf; \
	kubectl get nodes -o wide; echo; \
	kubectl get gatewayclass,gateway,httproute -A; echo; \
	kubectl get pods -A -o wide

destroy: ## Tear the cluster down (kubeadm reset); packages and credentials are kept
	$(ANSIBLE_ENV) ansible-playbook -i $(INVENTORY) ansible/reset.yml

diagnostics: ## Collect cluster diagnostics into ./diagnostics
	./scripts/collect-diagnostics.sh diagnostics

lint: ## Static checks: yamllint, ansible-lint, shellcheck, kustomize build + kubeconform
	./scripts/lint.sh

dashboard: ## Regenerate the Grafana dashboard JSON from tools/gen-dashboard.py
	python3 tools/gen-dashboard.py
