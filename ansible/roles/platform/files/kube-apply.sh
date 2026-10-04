#!/usr/bin/env bash
# Idempotent `kubectl apply -k <dir>` used by the Ansible platform role.
#
# Client-side apply of custom resources whose lists get server-side defaults
# (HTTPRoute rules, Envoy Gateway policies, ...) always reports "configured",
# although nothing changes. `kubectl diff` performs a server-side dry run with
# defaulting, so we apply only when the live state really differs.
# Prints NO_CHANGES when everything is already up to date.
#   KUBECTL="kubectl --kubeconfig ..." kube-apply.sh <kustomization-dir>
set -uo pipefail

read -ra kubectl_cmd <<<"${KUBECTL:-kubectl}"
dir=$1

"${kubectl_cmd[@]}" diff -k "$dir" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  echo "NO_CHANGES"
  exit 0
fi
# rc=1: differences found; rc>1: diff not possible yet (e.g. a webhook is still
# starting) - let apply do the work and report its own errors.
exec "${kubectl_cmd[@]}" apply -k "$dir"
