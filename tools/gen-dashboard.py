#!/usr/bin/env python3
"""Generates k8s/observability/dashboards/kube-gateway-lab.json (Grafana dashboard).

Kept as code so the dashboard is reviewable and reproducible:
    python3 tools/gen-dashboard.py
"""
import json
import pathlib

DS = {"type": "prometheus", "uid": "${datasource}"}
DEMO = 'envoy_cluster_name=~"httproute/demo/.*"'
_next_id = [0]


def pid():
    _next_id[0] += 1
    return _next_id[0]


def target(expr, legend="", ref="A", instant=False):
    t = {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": ref, "range": not instant}
    if instant:
        t["instant"] = True
    return t


def stat(title, expr, x, y, unit="short", w=4, h=4, thresholds=None, decimals=None, desc=""):
    steps = thresholds or [{"color": "green", "value": None}]
    p = {
        "id": pid(), "type": "stat", "title": title, "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [target(expr)],
        "fieldConfig": {"defaults": {"unit": unit, "thresholds": {"mode": "absolute", "steps": steps}},
                        "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "background", "graphMode": "area", "textMode": "auto"},
    }
    if decimals is not None:
        p["fieldConfig"]["defaults"]["decimals"] = decimals
    return p


def ts(title, targets, x, y, unit="short", w=12, h=8, desc="", stack=False):
    return {
        "id": pid(), "type": "timeseries", "title": title, "description": desc, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": targets,
        "fieldConfig": {"defaults": {"unit": unit, "custom": {
            "drawStyle": "line", "lineWidth": 1, "fillOpacity": 10, "showPoints": "never",
            "stacking": {"mode": "normal" if stack else "none", "group": "A"}}}, "overrides": []},
        "options": {"legend": {"displayMode": "table", "placement": "bottom", "calcs": ["mean", "max", "lastNotNull"]},
                    "tooltip": {"mode": "multi", "sort": "desc"}},
    }


def row(title, y):
    return {"id": pid(), "type": "row", "title": title, "collapsed": False,
            "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []}


RATE = "$__rate_interval"
panels = [
    row("Overview", 0),
    stat("Gateway RPS (demo)", f'sum(rate(envoy_cluster_upstream_rq_total{{{DEMO}}}[{RATE}]))', 0, 1, "reqps", decimals=2,
         desc="Requests per second routed by Envoy Gateway to the demo namespace"),
    stat("5xx ratio (5m)",
         f'(sum(rate(envoy_cluster_upstream_rq_xx{{{DEMO},envoy_response_code_class="5"}}[5m])) or vector(0))'
         f' / clamp_min(sum(rate(envoy_cluster_upstream_rq_total{{{DEMO}}}[5m])), 1e-9)',
         4, 1, "percentunit", decimals=2,
         thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 0.01}, {"color": "red", "value": 0.05}]),
    stat("p95 latency (5m)",
         f'histogram_quantile(0.95, sum by (le) (rate(envoy_cluster_upstream_rq_time_bucket{{{DEMO}}}[5m])))',
         8, 1, "ms", decimals=1,
         thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 200}, {"color": "red", "value": 500}]),
    stat("hello pods ready", 'sum(kube_deployment_status_replicas_available{namespace="demo"})', 12, 1,
         thresholds=[{"color": "red", "value": None}, {"color": "green", "value": 1}]),
    stat("Logs shipped /s (Fluentd)", f'sum(rate(fluentd_output_status_emit_records[{RATE}]))', 16, 1, "short", decimals=1),
    stat("Scrape targets up", 'sum(up) / count(up)', 20, 1, "percentunit", decimals=0,
         thresholds=[{"color": "red", "value": None}, {"color": "orange", "value": 0.9}, {"color": "green", "value": 1}]),

    row("Gateway API / Envoy (RED)", 5),
    ts("Requests by response class", [
        target(f'sum by (envoy_response_code_class) (rate(envoy_cluster_upstream_rq_xx{{{DEMO}}}[{RATE}]))',
               "{{envoy_response_code_class}}xx")], 0, 6, "reqps", stack=True),
    ts("Upstream latency", [
        target(f'histogram_quantile(0.50, sum by (le) (rate(envoy_cluster_upstream_rq_time_bucket{{{DEMO}}}[{RATE}])))', "p50", "A"),
        target(f'histogram_quantile(0.95, sum by (le) (rate(envoy_cluster_upstream_rq_time_bucket{{{DEMO}}}[{RATE}])))', "p95", "B"),
        target(f'histogram_quantile(0.99, sum by (le) (rate(envoy_cluster_upstream_rq_time_bucket{{{DEMO}}}[{RATE}])))', "p99", "C"),
    ], 12, 6, "ms"),
    ts("Requests per HTTPRoute rule (all namespaces)", [
        target(f'sum by (envoy_cluster_name) (rate(envoy_cluster_upstream_rq_total{{envoy_cluster_name=~"httproute/.*"}}[{RATE}]))',
               "{{envoy_cluster_name}}")], 0, 14, "reqps"),
    ts("Downstream connections & rate-limited requests", [
        target('sum(envoy_http_downstream_cx_active)', "active client connections", "A"),
        target(f'sum(rate(envoy_http_local_rate_limit_rate_limited[{RATE}]))', "rate-limited req/s (429)", "B"),
    ], 12, 14, "short"),

    row("Demo application (nginx)", 22),
    ts("nginx requests by version (canary split)", [
        target(f'sum by (app_kubernetes_io_version) (rate(nginx_http_requests_total{{job="hello"}}[{RATE}]))',
               "{{app_kubernetes_io_version}}")], 0, 23, "reqps", w=8,
       desc="Counted by nginx itself (includes kubelet probes)"),
    ts("CPU by pod", [
        target(f'sum by (pod) (rate(container_cpu_usage_seconds_total{{namespace="demo",container!="",container!="POD"}}[{RATE}]))',
               "{{pod}}")], 8, 23, "cores", w=8),
    ts("Memory (working set) by pod", [
        target('sum by (pod) (container_memory_working_set_bytes{namespace="demo",container!="",container!="POD"})',
               "{{pod}}")], 16, 23, "bytes", w=8),

    row("Logging pipeline (Fluentd -> OpenSearch)", 31),
    ts("Records shipped per output", [
        target(f'sum by (plugin_id) (rate(fluentd_output_status_emit_records[{RATE}]))', "{{plugin_id}}")],
       0, 32, "short", w=8),
    ts("Buffer queue length", [
        target('sum by (plugin_id) (fluentd_output_status_buffer_queue_length)', "{{plugin_id}}")], 8, 32, "short", w=8),
    ts("Retries / errors", [
        target('sum by (plugin_id) (fluentd_output_status_retry_count)', "retries {{plugin_id}}", "A"),
        target('sum by (plugin_id) (fluentd_output_status_num_errors)', "errors {{plugin_id}}", "B"),
    ], 16, 32, "short", w=8),
]

dashboard = {
    "uid": "kube-gateway-lab",
    "title": "kube-gateway-lab: Gateway, App & Logging",
    "tags": ["kube-gateway-lab", "gateway-api", "envoy", "fluentd"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "editable": True,
    "refresh": "30s",
    "time": {"from": "now-1h", "to": "now"},
    "templating": {"list": [{
        "name": "datasource", "label": "Prometheus", "type": "datasource", "query": "prometheus",
        "current": {}, "hide": 0, "refresh": 1, "regex": "", "includeAll": False, "multi": False}]},
    "annotations": {"list": []},
    "panels": panels,
}

out = pathlib.Path(__file__).resolve().parent.parent / "k8s/observability/dashboards/kube-gateway-lab.json"
out.write_text(json.dumps(dashboard, indent=2) + "\n", encoding="utf-8", newline="\n")
print(f"wrote {out}")
