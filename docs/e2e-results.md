# Результаты e2e-проверки на Ubuntu 24.04

Источник: GitHub Actions, workflow `ci`, job **«E2E - kubeadm cluster on Ubuntu 24.04»**,
[run #10](https://github.com/SharPixX/hack/actions/runs/37205964156) (коммит `5c16c91`), 2026-10-04.
Раннер: чистая ВМ `ubuntu-24.04` (Ubuntu 24.04 LTS, x86_64, 4 vCPU, 16 GB RAM).
Этот же сценарий выполняется на каждый push в `main` — актуальный статус показывает бейдж в README.

Сценарий job:
1. `sudo ./deploy.sh` — развёртывание с нуля (kubeadm + платформа + приложение + smoke-test);
2. `sudo SKIP_VERIFY=1 ./deploy.sh` — **повторный запуск** на том же узле (проверка идемпотентности);
3. `sudo ./scripts/smoke-test.sh` — проверка после повторного запуска (вывод ниже).

Итоги smoke-test и `PLAY RECAP` второго прогона публикуются в CI как аннотации (notice) и видны
на странице run без входа в GitHub. Полные логи и диагностика (поды, события, таргеты Prometheus,
индексы OpenSearch, логи контейнеров) сохраняются как artifact `e2e-ubuntu-24.04`.

## Повторный деплой (идемпотентность)

```
PLAY RECAP *********************************************************************
localhost                  : ok=94   changed=3    unreachable=0    failed=0    skipped=12   rescued=0    ignored=0
```

`failed=0`, состояние кластера не меняется. Три задачи `kubectl apply -k` с ресурсами Gateway API
сообщали `configured` из-за значений по умолчанию, которые API-сервер добавляет в списки CRD (например,
`HTTPRoute.rules[].backendRefs[].weight`). Поэтому применение манифестов переведено на
`kubectl diff` → `apply` только при реальной разнице ([`kube-apply.sh`](../ansible/roles/platform/files/kube-apply.sh)).

## Smoke-test после повторного деплоя: 56 passed, 0 failed

```
== Kubernetes cluster
  [PASS] API server reachable (v1.36.5)
  [PASS] all 1 node(s) Ready
  [PASS] pods Ready in namespace kube-system
  [PASS] pods Ready in namespace calico-system
  [PASS] pods Ready in namespace tigera-operator
  [PASS] pods Ready in namespace metallb-system
  [PASS] pods Ready in namespace envoy-gateway-system
  [PASS] pods Ready in namespace cert-manager
  [PASS] pods Ready in namespace monitoring
  [PASS] pods Ready in namespace logging
  [PASS] pods Ready in namespace demo

== Gateway API (Envoy Gateway)
  [PASS] GatewayClass envoy-gateway Accepted
  [PASS] Gateway edge/public Programmed, address 10.1.0.138
  [PASS] HTTPRoute demo/hello Accepted, refs resolved
  [PASS] HTTPRoute demo/hello-limited Accepted, refs resolved
  [PASS] HTTPRoute edge/https-redirect Accepted, refs resolved
  [PASS] HTTPRoute logging/opensearch-dashboards Accepted, refs resolved
  [PASS] HTTPRoute monitoring/alertmanager Accepted, refs resolved
  [PASS] HTTPRoute monitoring/grafana Accepted, refs resolved
  [PASS] HTTPRoute monitoring/prometheus Accepted, refs resolved
  [PASS] HTTP  http://hello.lab.test/ -> "Hello World!"
  [PASS] HTTPS https://hello.lab.test/ -> "Hello World!" (certificate verified with the lab CA)
  [PASS] ResponseHeaderModifier filter adds 'x-served-via: envoy-gateway'
  [PASS] header match: 'X-Canary: always' -> v2
  [PASS] path match + URLRewrite: /v1/info -> v1, /v2/info -> v2
  [PASS] HTTP->HTTPS redirect for operator UIs: 301 https://grafana.lab.test/
  [PASS] SecurityPolicy basic auth: prometheus without credentials -> 401
  [PASS] SecurityPolicy basic auth: prometheus with credentials -> 200
  [PASS] Grafana published at https://grafana.lab.test -> 200
  [PASS] OpenSearch Dashboards published at https://logs.lab.test, protected (401 without credentials)
  [PASS] traffic split 90/10: 21/200 (10%) requests served by v2
  [PASS] local rate limit on /limited (5 rps):      10 200      15 429

== Monitoring (Prometheus)
  [PASS] Prometheus is ready
  [PASS] target kube-apiserver up (1/1)
  [PASS] target kubelet + cAdvisor up (3/3)
  [PASS] target etcd up (1/1)
  [PASS] target kube-controller-manager up (1/1)
  [PASS] target kube-scheduler up (1/1)
  [PASS] target kube-proxy up (1/1)
  [PASS] target CoreDNS up (2/2)
  [PASS] target node-exporter up (1/1)
  [PASS] target kube-state-metrics up (1/1)
  [PASS] target cert-manager up (1/1)
  [PASS] target hello app (nginx exporter) up (3/3)
  [PASS] target Envoy proxies of the Gateway up (2/2)
  [PASS] target Envoy Gateway controller up (1/1)
  [PASS] target Fluentd up (1/1)
         scrape jobs: kps-prometheus=2 kps-alertmanager=2 kube-etcd=1 grafana=1 coredns=2 kps-operator=1 kubelet=3 kube-state-metrics=1 kube-scheduler=1 kube-controller-manager=1 apiserver=1 node-exporter=1 kube-proxy=1 metallb-controller-monitor-service=1 metallb=1 cainjector=1 cert-manager=1 webhook=1 hello=3 logging/fluentd=1 envoy-gateway-system/envoy-proxy=2 envoy-gateway=1
  [PASS] gateway requests to demo (envoy_cluster_upstream_rq_total) = 262
  [PASS] gateway 5xx responses (envoy_cluster_upstream_rq_xx{class=5}) = 20
  [PASS] nginx requests (nginx_http_requests_total) = 572
  [PASS] Fluentd shipped records (fluentd_output_status_emit_records) = 11402
  [PASS] recording rule hello:gateway_requests:rate1m = 0.04444444444444444
  [PASS] custom alerting/recording rule groups loaded: 4 (alerts currently active: 0)
== Logging (Fluentd -> OpenSearch)
         sent requests tagged with marker smoke17911215485226, waiting for them in OpenSearch...
  [PASS] nginx ACCESS log found in index app-demo-*: {"@timestamp":"2026-10-04T13:45:48.699250780+00:00","method":"GET","uri":"/?probe=smoke17911215485226","status":200,"app_version":"v1","pod":"hello-v1-8689f55bc4-jt5gj"}
  [PASS] nginx ERROR log found in index app-demo-*: 2026/10/04 13:45:48 [error] 21#21: *86 access forbidden by rule, client: 10.244.159.85, server: _, request: "GET /stub_status?probe=smoke179
  [PASS] Envoy Gateway access log found in index gateway-access-*: {"authority":"hello.lab.test","path":"/?probe=smoke17911215485226","response_code":200,"upstream_cluster":"httproute/demo/hello/rule/3","request_id":"a9a67129-56c1-4190-b462-8d5e3992ff9a"}
         indices: .kibana_1 4 .plugins-ml-config 1 app-demo-2026.10.04 556 gateway-access-2026.10.04 580 k8s-logs-2026.10.04 9774 top_queries-2026.10.04-59463 8

== Result
  56 passed, 0 failed
  ALL CHECKS PASSED
```

Примечания:
- `traffic split` проверяется статистически: из 200 запросов доля v2 должна быть в диапазоне 3–22% (ожидаемо ~10%).
- Если в выводе `alerts currently active` > 0 — это `HelloHigh5xxRatio` в состоянии pending: smoke-test
  специально шлёт запросы на `/error` (HTTP 500), чтобы проверить метрики 5xx и работу алертинга.
