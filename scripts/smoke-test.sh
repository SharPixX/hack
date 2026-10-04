#!/usr/bin/env bash
# End-to-end verification of kube-gateway-lab.
#
#   sudo ./scripts/smoke-test.sh        (or: make verify)
#
# Checks the cluster, every Gateway API feature, Prometheus targets/queries and
# that a request made through the Gateway shows up in OpenSearch (Fluentd pipeline).
# Exit code is non-zero if any check fails. Read-only except for HTTP test traffic.
# ok() always returns 0, so `cond && ok ... || fail ...` is a safe if/else here
# shellcheck disable=SC2015
set -Eeuo pipefail

DOMAIN="${LAB_DOMAIN:-lab.test}"
SECRETS_DIR="${LAB_SECRETS_DIR:-/etc/kube-gateway-lab}"
if [[ -z "${KUBECONFIG:-}" ]]; then
  if [[ -r /etc/kubernetes/admin.conf ]]; then export KUBECONFIG=/etc/kubernetes/admin.conf
  else export KUBECONFIG="${HOME}/.kube/config"; fi
fi
KUBECTL="${KUBECTL:-kubectl}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
if [[ -t 1 ]]; then G=$'\e[32m'; R=$'\e[31m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'; else G=; R=; B=; D=; N=; fi

section() { printf '\n%s== %s%s\n' "$B" "$*" "$N"; }
ok()      { PASS=$((PASS + 1)); printf '  %s[PASS]%s %s\n' "$G" "$N" "$*"; }
fail()    { FAIL=$((FAIL + 1)); printf '  %s[FAIL]%s %s\n' "$R" "$N" "$*"; }
info()    { printf '         %s%s%s\n' "$D" "$*" "$N"; }

# retry <attempts> <sleep> <cmd...>
retry() {
  local n=$1 s=$2 i
  shift 2
  for ((i = 1; i <= n; i++)); do
    if "$@"; then return 0; fi
    sleep "$s"
  done
  return 1
}

# HTTP helper pinned to the Gateway IP (no DNS needed): gw_curl <host> <scheme> [curl args...] <path>
gw_curl() {
  local host=$1 scheme=$2
  shift 2
  local port=80
  [[ $scheme == https ]] && port=443
  local path="${*: -1}"
  local args=("${@:1:$#-1}")
  curl -sS --max-time 10 --resolve "${host}.${DOMAIN}:${port}:${GW_IP}" --cacert "$TMP/ca.crt" \
    "${args[@]}" "${scheme}://${host}.${DOMAIN}${path}"
}

uri_encode() { jq -rn --arg v "$1" '$v|@uri'; }

# Prometheus instant query through the API server service proxy (no port-forward needed)
prom_query() {
  "$KUBECTL" get --raw \
    "/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/query?query=$(uri_encode "$1")"
}

# OpenSearch search through the API server service proxy
os_search() {
  "$KUBECTL" get --raw \
    "/api/v1/namespaces/logging/services/opensearch-cluster-master:9200/proxy/$1/_search?q=$(uri_encode "$2")&size=1&sort=@timestamp:desc"
}

# ---------------------------------------------------------------------------
section "Kubernetes cluster"
if "$KUBECTL" get nodes >/dev/null 2>&1; then
  ok "API server reachable ($("$KUBECTL" version -o json | jq -r .serverVersion.gitVersion))"
else
  fail "API server not reachable with KUBECONFIG=$KUBECONFIG"
  exit 1
fi

not_ready=$("$KUBECTL" get nodes --no-headers | awk '$2 != "Ready"' | wc -l)
nodes=$("$KUBECTL" get nodes --no-headers | wc -l)
if [[ $not_ready -eq 0 ]]; then ok "all $nodes node(s) Ready"; else fail "$not_ready node(s) not Ready"; fi

for ns in kube-system calico-system tigera-operator metallb-system envoy-gateway-system cert-manager monitoring logging demo; do
  if "$KUBECTL" -n "$ns" wait --for=condition=Ready pod --all --field-selector=status.phase!=Succeeded --timeout=180s >/dev/null 2>&1; then
    ok "pods Ready in namespace $ns"
  else
    fail "not all pods Ready in namespace $ns"
    "$KUBECTL" -n "$ns" get pods --no-headers | awk '$3 != "Running" && $3 != "Completed" {print "         " $0}' || true
  fi
done

# ---------------------------------------------------------------------------
section "Gateway API (Envoy Gateway)"
gc=$("$KUBECTL" get gatewayclass envoy-gateway -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
[[ $gc == True ]] && ok "GatewayClass envoy-gateway Accepted" || fail "GatewayClass envoy-gateway not Accepted"

gw=$("$KUBECTL" -n edge get gateway public -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
GW_IP=$("$KUBECTL" -n edge get gateway public -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
if [[ $gw == True && -n $GW_IP ]]; then ok "Gateway edge/public Programmed, address $GW_IP"; else fail "Gateway edge/public not Programmed"; exit 1; fi

while read -r ns name accepted resolved; do
  if [[ $accepted == *True* && $accepted != *False* && $resolved != *False* ]]; then
    ok "HTTPRoute $ns/$name Accepted, refs resolved"
  else
    fail "HTTPRoute $ns/$name accepted=[$accepted] resolvedRefs=[$resolved]"
  fi
done < <("$KUBECTL" get httproute -A -o jsonpath='{range .items[*]}{.metadata.namespace} {.metadata.name} {.status.parents[*].conditions[?(@.type=="Accepted")].status} {.status.parents[*].conditions[?(@.type=="ResolvedRefs")].status}{"\n"}{end}' | sed 's/True True/True,True/g')

"$KUBECTL" -n cert-manager get secret lab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d >"$TMP/ca.crt"

body=$(retry 10 3 gw_curl hello http / || true)
[[ $body == "Hello World!" ]] && ok "HTTP  http://hello.$DOMAIN/ -> \"$body\"" || fail "HTTP  http://hello.$DOMAIN/ returned \"$body\""

body=$(gw_curl hello https / || true)
[[ $body == "Hello World!" ]] && ok "HTTPS https://hello.$DOMAIN/ -> \"$body\" (certificate verified with the lab CA)" \
  || fail "HTTPS https://hello.$DOMAIN/ returned \"$body\""

hdr=$(gw_curl hello http -D - -o /dev/null / | tr -d '\r' | grep -i '^x-served-via:' || true)
[[ $hdr == *envoy-gateway* ]] && ok "ResponseHeaderModifier filter adds '$hdr'" || fail "X-Served-Via header missing"

v=$(gw_curl hello http -H 'X-Canary: always' /info | jq -r .version 2>/dev/null || true)
[[ $v == v2 ]] && ok "header match: 'X-Canary: always' -> $v" || fail "header match returned '$v'"

v1=$(gw_curl hello http /v1/info | jq -r .version 2>/dev/null || true)
v2=$(gw_curl hello http /v2/info | jq -r .version 2>/dev/null || true)
[[ $v1 == v1 && $v2 == v2 ]] && ok "path match + URLRewrite: /v1/info -> $v1, /v2/info -> $v2" || fail "path routing: /v1 -> '$v1', /v2 -> '$v2'"

total=200
canary=0
for ((i = 0; i < total; i++)); do
  [[ $(gw_curl hello http /info | jq -r .version 2>/dev/null) == v2 ]] && canary=$((canary + 1))
done
pct=$((canary * 100 / total))
if ((pct >= 3 && pct <= 22)); then ok "traffic split 90/10: $canary/$total (${pct}%) requests served by v2"
else fail "traffic split: $canary/$total (${pct}%) served by v2, expected ~10%"; fi

codes=$(for _ in $(seq 25); do gw_curl hello http -o /dev/null -w '%{http_code}\n' /limited; done | sort | uniq -c | tr '\n' ' ')
[[ $codes == *429* && $codes == *200* ]] && ok "local rate limit on /limited (5 rps): $codes" || fail "rate limit not observed: $codes"

loc=$(gw_curl grafana http -o /dev/null -w '%{http_code} %{redirect_url}' / || true)
[[ $loc == "301 https://grafana.$DOMAIN/" ]] && ok "HTTP->HTTPS redirect for operator UIs: $loc" || fail "redirect returned '$loc'"

code=$(gw_curl prometheus https -o /dev/null -w '%{http_code}' /-/ready || true)
[[ $code == 401 ]] && ok "SecurityPolicy basic auth: prometheus without credentials -> $code" || fail "prometheus without credentials -> $code (expected 401)"
if [[ -r $SECRETS_DIR/ui-basic-auth-password ]]; then
  code=$(gw_curl prometheus https -u "admin:$(cat "$SECRETS_DIR/ui-basic-auth-password")" -o /dev/null -w '%{http_code}' /-/ready || true)
  [[ $code == 200 ]] && ok "SecurityPolicy basic auth: prometheus with credentials -> $code" || fail "prometheus with credentials -> $code"
fi
code=$(gw_curl grafana https -o /dev/null -w '%{http_code}' /api/health || true)
[[ $code == 200 ]] && ok "Grafana published at https://grafana.$DOMAIN -> $code" || fail "Grafana via Gateway -> $code"

# ---------------------------------------------------------------------------
section "Monitoring (Prometheus)"
for _ in $(seq 20); do gw_curl hello http -o /dev/null / ; gw_curl hello http -o /dev/null /error; done || true

if retry 12 5 sh -c "\"$KUBECTL\" get --raw /api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/-/ready >/dev/null 2>&1"; then
  ok "Prometheus is ready"
else
  fail "Prometheus is not ready"
fi

prom_query 'sum by (job) (up)' | jq -r '.data.result[] | "\(.metric.job) \(.value[1])"' | sort >"$TMP/up.txt" || true
prom_query 'count by (job) (up)' | jq -r '.data.result[] | "\(.metric.job) \(.value[1])"' | sort >"$TMP/all.txt" || true
for job in apiserver kubelet node-exporter kube-state-metrics kube-etcd kube-controller-manager kube-scheduler kube-proxy coredns \
  hello envoy-gateway-system/envoy-proxy envoy-gateway logging/fluentd cert-manager; do
  up=$(awk -v j="$job" '$1 == j {print $2}' "$TMP/up.txt")
  all=$(awk -v j="$job" '$1 == j {print $2}' "$TMP/all.txt")
  if [[ -n $up && $up != 0 && $up == "$all" ]]; then ok "target job=\"$job\" up ($up/$all)"; else fail "target job=\"$job\" up=${up:-0}/${all:-0}"; fi
done

check_metric() {
  local desc=$1 q=$2 val
  val=$(prom_query "$q" | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true)
  if [[ -n $val ]] && awk -v v="$val" 'BEGIN{exit !(v > 0)}'; then ok "$desc = $val"; return 0; fi
  return 1
}
retry 12 5 check_metric "gateway requests to demo (envoy_cluster_upstream_rq_total)" \
  'sum(envoy_cluster_upstream_rq_total{envoy_cluster_name=~"httproute/demo/.*"})' || fail "no Envoy request metrics for demo routes"
retry 12 5 check_metric "gateway 5xx responses (envoy_cluster_upstream_rq_xx{class=5})" \
  'sum(envoy_cluster_upstream_rq_xx{envoy_cluster_name=~"httproute/demo/.*",envoy_response_code_class="5"})' || fail "no 5xx metrics"
retry 12 5 check_metric "nginx requests (nginx_http_requests_total)" 'sum(nginx_http_requests_total{job="hello"})' || fail "no nginx metrics"
retry 12 5 check_metric "Fluentd shipped records (fluentd_output_status_emit_records)" 'sum(fluentd_output_status_emit_records)' || fail "no Fluentd metrics"
retry 6 5 check_metric "recording rule hello:gateway_requests:rate1m" 'hello:gateway_requests:rate1m' || info "recording rule has no data yet (needs ~1m of traffic)"
rules=$(prom_query 'count(ALERTS{alertname=~"Hello.*|Gateway.*|Fluentd.*"}) or vector(0)' | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "?")
groups=$("$KUBECTL" get --raw /api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy/api/v1/rules |
  jq '[.data.groups[] | select(.name | test("^(hello|gateway|logging)"))] | length' 2>/dev/null || echo 0)
((groups >= 4)) && ok "custom alerting/recording rule groups loaded: $groups (alerts currently active: $rules)" || fail "custom rule groups loaded: $groups"

# ---------------------------------------------------------------------------
section "Logging (Fluentd -> OpenSearch)"
marker="smoke$(date +%s)$RANDOM"
gw_curl hello http -o /dev/null -A "smoke-test/$marker" "/?probe=$marker" || true
gw_curl hello http -o /dev/null "/stub_status?probe=$marker" || true # 403 -> nginx error log line
info "sent requests tagged with marker $marker, waiting for them in OpenSearch..."

find_log() {
  local index=$1 query=$2
  os_search "$index" "$query" >"$TMP/hit.json" 2>/dev/null || return 1
  [[ $(jq -r '.hits.total.value // 0' "$TMP/hit.json") -ge 1 ]]
}
if retry 30 4 find_log 'app-demo-*' "uri:*${marker}* AND log_type:access"; then
  ok "nginx ACCESS log found in index app-demo-*: $(jq -c '.hits.hits[0]._source | {"@timestamp", method, uri, status, app_version, pod: .kubernetes.pod_name}' "$TMP/hit.json")"
else
  fail "access log with marker $marker not found in app-demo-*"
fi
if retry 15 4 find_log 'app-demo-*' "log_type:error AND ${marker}"; then
  ok "nginx ERROR log found in index app-demo-*: $(jq -r '.hits.hits[0]._source.log' "$TMP/hit.json" | cut -c1-140)"
else
  fail "error log with marker $marker not found in app-demo-*"
fi
if retry 15 4 find_log 'gateway-access-*' "${marker}"; then
  ok "Envoy Gateway access log found in index gateway-access-*: $(jq -c '.hits.hits[0]._source | {authority, path, response_code, upstream_cluster, request_id}' "$TMP/hit.json")"
else
  fail "gateway access log with marker $marker not found in gateway-access-*"
fi
count=$("$KUBECTL" get --raw '/api/v1/namespaces/logging/services/opensearch-cluster-master:9200/proxy/_cat/indices?h=index,docs.count' 2>/dev/null | sort | tr '\n' ' ' || true)
[[ -n $count ]] && info "indices: $count"

# ---------------------------------------------------------------------------
section "Result"
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
if ((FAIL > 0)); then
  printf '  %sSMOKE TEST FAILED%s\n' "$R" "$N"
  exit 1
fi
printf '  %sALL CHECKS PASSED%s\n' "$G" "$N"
