#!/usr/bin/env bash
# Collects cluster state for troubleshooting (used by CI as a build artifact).
#   sudo ./scripts/collect-diagnostics.sh [output-dir]
# Secrets are never dumped (only their names).
set -uo pipefail

OUT="${1:-diagnostics}"
export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
mkdir -p "$OUT/logs"

run() { local f=$1; shift; { echo "\$ $*"; "$@"; } >"$OUT/$f" 2>&1; }

run nodes.txt kubectl get nodes -o wide
run pods.txt kubectl get pods -A -o wide
run events.txt kubectl get events -A --sort-by=.lastTimestamp
run gateway-api.txt kubectl get gatewayclass,gateway,httproute,referencegrant -A -o wide
run gateway-api.yaml kubectl get gatewayclass,gateway,httproute -A -o yaml
run envoy-policies.yaml kubectl get envoyproxy,clienttrafficpolicy,backendtrafficpolicy,securitypolicy -A -o yaml
run services.txt kubectl get svc,endpointslices -A -o wide
run helm.txt helm list -A
run certificates.txt kubectl get certificates,certificaterequests,clusterissuers -A
run monitoring-crs.txt kubectl get servicemonitors,podmonitors,prometheusrules -A
run tigerastatus.txt kubectl get tigerastatus -o wide
run pvc.txt kubectl get pvc,pv -A
run top.txt kubectl top pods -A
run secrets-names.txt kubectl get secrets -A
run describe-not-ready.txt bash -c "kubectl get pods -A --no-headers | awk '\$4 != \"Running\" && \$4 != \"Completed\" {print \$1, \$2}' | while read -r ns p; do kubectl -n \"\$ns\" describe pod \"\$p\"; done"
run prometheus-targets.json kubectl get --raw '/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/targets?state=active'
run opensearch-indices.txt kubectl get --raw '/api/v1/namespaces/logging/services/opensearch-cluster-master:9200/proxy/_cat/indices?v'
run kubelet.log journalctl -u kubelet --no-pager -n 300
run containerd.log journalctl -u containerd --no-pager -n 200

kubectl get pods -A --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name |
  while read -r ns pod; do
    kubectl -n "$ns" logs "$pod" --all-containers --tail=200 >"$OUT/logs/${ns}_${pod}.log" 2>&1
  done

echo "diagnostics written to $OUT/"
