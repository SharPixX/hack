#!/usr/bin/env python3
"""Builds the solution passport (docs/passport/Паспорт.pdf), max 4 pages A4.

    pip install reportlab && python3 docs/passport/build_passport.py
"""
import pathlib
import sys

from reportlab.graphics.shapes import Drawing, Line, Polygon, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table,
                                TableStyle)

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "Паспорт.pdf"
REPO = "https://github.com/SharPixX/hack"

# ------------------------------------------------------------------ fonts (Cyrillic)
FONT_CANDIDATES = [
    ("C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/ariali.ttf"),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
     "/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf"),
]
for regular, bold, italic in FONT_CANDIDATES:
    if pathlib.Path(regular).exists():
        pdfmetrics.registerFont(TTFont("Body", regular))
        pdfmetrics.registerFont(TTFont("Body-Bold", bold))
        pdfmetrics.registerFont(TTFont("Body-Italic", italic))
        pdfmetrics.registerFontFamily("Body", normal="Body", bold="Body-Bold", italic="Body-Italic",
                                      boldItalic="Body-Bold")
        break
else:
    sys.exit("no TTF font with Cyrillic glyphs found (install fonts-dejavu-core)")

INK = colors.HexColor("#1f2937")
MUTED = colors.HexColor("#4b5563")
ACCENT = colors.HexColor("#1d4ed8")
GRID = colors.HexColor("#cbd5e1")
HEAD_BG = colors.HexColor("#e8eefc")

H1 = ParagraphStyle("h1", fontName="Body-Bold", fontSize=13.5, leading=16, textColor=ACCENT, spaceAfter=3)
H2 = ParagraphStyle("h2", fontName="Body-Bold", fontSize=10.5, leading=13, textColor=INK, spaceBefore=5,
                    spaceAfter=3)
P = ParagraphStyle("p", fontName="Body", fontSize=8.6, leading=11, textColor=INK, alignment=TA_LEFT)
SMALL = ParagraphStyle("s", parent=P, fontSize=7.6, leading=9.4)
CELL = ParagraphStyle("c", parent=P, fontSize=7.4, leading=9.0)
CELLB = ParagraphStyle("cb", parent=CELL, fontName="Body-Bold")
MONO = "Courier"


def table(rows, widths, head=True, style=CELL):
    data = [[Paragraph(str(c), CELLB if (head and i == 0) else style) for c in r] for i, r in enumerate(rows)]
    t = Table(data, colWidths=widths, repeatRows=1 if head else 0)
    cmds = [
        ("GRID", (0, 0), (-1, -1), 0.4, GRID),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
        ("TOPPADDING", (0, 0), (-1, -1), 1.6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]
    if head:
        cmds.append(("BACKGROUND", (0, 0), (-1, 0), HEAD_BG))
    t.setStyle(TableStyle(cmds))
    return t


# ------------------------------------------------------------------ architecture diagram
def box(d, x, y, w, h, lines, fill, stroke=colors.HexColor("#64748b"), bold_first=True, size=6.6, dash=None):
    d.add(Rect(x, y, w, h, rx=3, ry=3, fillColor=fill, strokeColor=stroke, strokeWidth=0.7,
               strokeDashArray=dash))
    top = y + h - size - 3
    for i, text in enumerate(lines):
        d.add(String(x + w / 2, top - i * (size + 1.6), text, fontName="Body-Bold" if (i == 0 and bold_first) else "Body",
                     fontSize=size, fillColor=INK, textAnchor="middle"))


def arrow(d, x1, y1, x2, y2, color=colors.HexColor("#334155"), dash=None, width=0.9):
    d.add(Line(x1, y1, x2, y2, strokeColor=color, strokeWidth=width, strokeDashArray=dash))
    import math
    ang = math.atan2(y2 - y1, x2 - x1)
    s = 4.2
    p1 = (x2 - s * math.cos(ang - 0.4), y2 - s * math.sin(ang - 0.4))
    p2 = (x2 - s * math.cos(ang + 0.4), y2 - s * math.sin(ang + 0.4))
    d.add(Polygon([x2, y2, p1[0], p1[1], p2[0], p2[1]], fillColor=color, strokeColor=color, strokeWidth=0.3))


def label(d, x, y, text, size=5.8, color=MUTED, anchor="middle"):
    d.add(String(x, y, text, fontName="Body-Italic", fontSize=size, fillColor=color, textAnchor=anchor))


def diagram():
    W, H = 515, 292
    d = Drawing(W, H)
    # cluster frame
    d.add(Rect(92, 22, 421, 262, rx=5, ry=5, fillColor=colors.HexColor("#f8fafc"),
               strokeColor=colors.HexColor("#94a3b8"), strokeWidth=0.9))
    d.add(String(98, 274, "Узел Ubuntu 24.04 LTS  ·  kubeadm v1.36.5  ·  containerd 2.2.9  ·  Calico 3.32 (CNI + NetworkPolicy)",
                 fontName="Body-Bold", fontSize=6.9, fillColor=INK))

    blue = colors.HexColor("#dbeafe")
    green = colors.HexColor("#dcfce7")
    orange = colors.HexColor("#ffedd5")
    violet = colors.HexColor("#ede9fe")
    grey = colors.HexColor("#f1f5f9")

    box(d, 2, 196, 80, 40, ["Пользователь", "curl / браузер", "*.lab.test"], colors.white)
    box(d, 100, 196, 70, 40, ["MetalLB (L2)", "LoadBalancer", "IP узла :80 / :443"], grey)
    box(d, 184, 168, 126, 96, ["Gateway API", "Envoy Gateway v1.9.2", "GatewayClass envoy-gateway",
                                "Gateway edge/public", "listeners HTTP:80, HTTPS:443", "HTTPRoute ×7 · TLS terminate",
                                "Envoy proxy ×2 (+PDB)", "Client/Backend/Security", "Policy (rate limit, auth)"], blue)
    box(d, 330, 240, 176, 26, ["cert-manager", "свой CA → wildcard *.lab.test (auto-rotate)"], grey)
    box(d, 330, 188, 84, 44, ["hello-v1  (90%)", "nginx + exporter", "HPA 2–5, PDB"], green)
    box(d, 422, 188, 84, 44, ["hello-v2  (10%)", "canary · X-Canary", "/v2/* · rate /limited"], green)
    box(d, 330, 146, 112, 34, ["Grafana · Prometheus", "Alertmanager · OSD", "HTTPS, basic auth"], violet)
    d.add(String(332, 182, "ns demo: NetworkPolicy default-deny, PSA restricted", fontName="Body-Italic",
                 fontSize=5.4, fillColor=MUTED))

    box(d, 100, 30, 200, 112, ["monitoring · kube-prometheus-stack (Helm)", "Prometheus Operator → Prometheus",
                               "ServiceMonitor / PodMonitor:", "Envoy (RPS, коды, latency p50/95/99)",
                               "nginx-exporter · Fluentd · cert-manager · MetalLB",
                               "apiserver · etcd · scheduler · controller-manager", "kubelet/cAdvisor · kube-proxy · CoreDNS",
                               "node-exporter · kube-state-metrics", "→ Grafana: дашборд как код",
                               "→ Alertmanager: SLO-алерты, recording rules"], orange, size=6.3)
    box(d, 312, 30, 194, 112, ["logging (Fluentd → OpenSearch)", "Fluentd v1.19.3 DaemonSet",
                               "tail /var/log/containers (CRI)", "kubernetes_metadata, JSON-парсинг",
                               "file buffer + pos в hostPath", "→ OpenSearch 3.9 (Helm, PVC):",
                               "app-demo-* · gateway-access-* · k8s-logs-*", "ISM: удаление через 7 дней",
                               "→ OpenSearch Dashboards", "корреляция по request_id"], violet, size=6.3)

    arrow(d, 82, 216, 100, 216)
    arrow(d, 170, 216, 184, 216)
    arrow(d, 310, 222, 330, 212)
    arrow(d, 310, 236, 440, 232.5, width=0.7)
    arrow(d, 310, 180, 330, 166)
    arrow(d, 400, 240, 310, 250, dash=[2, 2])
    label(d, 356, 254, "", 5)
    label(d, 205, 286, "")
    # logs
    arrow(d, 470, 188, 470, 142, color=colors.HexColor("#7c3aed"), dash=[2, 2])
    arrow(d, 290, 168, 322, 142, color=colors.HexColor("#7c3aed"), dash=[2, 2])
    label(d, 474, 166, "логи", color=colors.HexColor("#6d28d9"), anchor="start")
    label(d, 474, 159, "stdout/", color=colors.HexColor("#6d28d9"), anchor="start")
    label(d, 474, 152, "stderr", color=colors.HexColor("#6d28d9"), anchor="start")
    # metrics
    arrow(d, 210, 142, 220, 168, color=colors.HexColor("#c2410c"), dash=[3, 2])
    label(d, 168, 152, "scrape /metrics", color=colors.HexColor("#c2410c"))
    label(d, 215, 228, "", 5)

    d.add(String(98, 10, "Развёртывание: sudo ./deploy.sh → Ansible (роли) → Helm + Kustomize · "
                         "CI: GitHub Actions — lint + e2e на ubuntu-24.04",
                 fontName="Body", fontSize=6.6, fillColor=MUTED))
    return d


# ------------------------------------------------------------------ content
def page1():
    s = [Paragraph("Паспорт решения: kube-gateway-lab", H1),
         Paragraph(f"Репозиторий: <font color='#1d4ed8'>{REPO}</font> (ветка main). Развёртывание одной командой "
                   "<font face='Courier'>sudo ./deploy.sh</font> на чистой Ubuntu 24.04; в конце автоматически "
                   "выполняется сквозной smoke-test (56 проверок).", P),
         Paragraph("1. Архитектура и состав решения", H2)]
    rows = [
        ["Параметр", "Значение"],
        ["Версия Kubernetes", "<b>v1.36.5</b> (kubeadm/kubelet/kubectl из pkgs.k8s.io, пакеты на hold). "
                              "1.36 — новейшая minor-версия, поддерживаемая всем стеком (Envoy Gateway 1.9, Calico 3.32)"],
        ["Способ развёртывания Kubernetes", "<b>kubeadm</b> (конфиг v1beta4 из шаблона), containerd 2.2.9 + runc 1.4.3 + CNI plugins "
                                            "1.9.1 из официальных релизов с проверкой sha256, CNI Calico (VXLAN). "
                                            "По умолчанию single-node, multi-node — через Ansible inventory (kubeadm join)"],
        ["Реализация Gateway API", "<b>Envoy Gateway v1.9.2</b> (Gateway API v1.6.1, Envoy 1.39); LoadBalancer — MetalLB 0.16 (L2); "
                                   "TLS — cert-manager 1.21"],
        ["Инструменты автоматизации", "<b>Ansible</b> (ansible-core 2.21, 7 ролей) + <b>Helm</b> 3.22 (через kubernetes.core.helm) + "
                                      "<b>Kustomize</b>; обёртки deploy.sh / Makefile; <b>GitHub Actions</b> (lint + e2e)"],
        ["Инструмент логирования", "<b>Fluentd v1.19.3</b> (DaemonSet) → OpenSearch 3.9 → OpenSearch Dashboards"],
        ["Способ развёртывания Prometheus", "Helm-чарт <b>kube-prometheus-stack 91.9.0</b> (Prometheus Operator v0.94): "
                                           "Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics; "
                                           "таргеты — ServiceMonitor/PodMonitor"],
        ["ОС, на которой тестировалось", "<b>Ubuntu 24.04 LTS</b>: e2e-деплой на чистом раннере GitHub Actions ubuntu-24.04 "
                                         "(x86_64, 4 vCPU/16 GB) на каждый push — двойной прогон + smoke-test. "
                                         "Результат: <b>56/56 проверок PASS</b>, повторный деплой changed=0, failed=0 "
                                         "(docs/e2e-results.md)"],
    ]
    s.append(table(rows, [44 * mm, 136 * mm]))
    s.append(Spacer(1, 5))
    s.append(Paragraph("Архитектурная схема: пользователь → Gateway API → приложение, мониторинг и логирование", H2))
    s.append(diagram())
    s.append(Paragraph("Проверка за минуту (на узле Ubuntu 24.04)", H2))
    cmds = [
        ["git clone https://github.com/SharPixX/hack.git && cd hack && sudo ./deploy.sh",
         "развернуть всё; в конце — smoke-test (56 проверок)"],
        ["curl http://hello.lab.test/", "Hello World! через Gateway API"],
        ["curl --cacert /opt/kube-gateway-lab/lab-ca.crt https://hello.lab.test/", "то же по HTTPS (свой CA)"],
        ["sudo make verify  |  sudo make credentials", "повторная проверка  |  адреса UI и пароли"],
    ]
    data = [[Paragraph(f"<font face='Courier'>{c}</font>", CELL), Paragraph(d, CELL)] for c, d in cmds]
    t = Table(data, colWidths=[112 * mm, 68 * mm])
    t.setStyle(TableStyle([("GRID", (0, 0), (-1, -1), 0.4, GRID), ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                           ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f8fafc")),
                           ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5)]))
    s.append(t)
    return s


def page2():
    s = [Paragraph("2. Реализованный функционал — обязательные требования", H2)]
    rows = [
        ["Требование", "Как реализовано технически", "Обоснование выбора", "Как проверить"],
        ["1. Kubernetes",
         "Ansible: node_prep (swap off, модули ядра, sysctl) → kube_packages → containerd → kubeadm init. "
         "Метрики etcd/scheduler/controller-manager/kube-proxy открыты для Prometheus в kubeadm-конфиге",
         "kubeadm — приоритет ТЗ, вендор-нейтрально; upstream-бинарники с sha256 — воспроизводимо и без Docker",
         "<font face='Courier'>kubectl get nodes -o wide</font>, <font face='Courier'>kubectl version</font>"],
        ["2. Веб-приложение",
         "nginx 1.30.5 (unprivileged) в 2 версиях: v1 (HPA 2–5) и v2 (canary). <b>GET /</b> → <b>Hello World!</b>; "
         "JSON access-лог → stdout, error-лог → stderr; sidecar nginx-prometheus-exporter",
         "Простой OSS-сервер, non-root образ; структурированные логи сразу пригодны для поиска",
         "<font face='Courier'>curl http://hello.lab.test/</font>"],
        ["3. Gateway API",
         "GatewayClass envoy-gateway (+EnvoyProxy) → Gateway edge/public (HTTP:80, HTTPS:443, allowedRoutes по метке "
         "namespace) → 7 HTTPRoute → Service hello-v1/v2. Адрес Gateway выдаёт MetalLB",
         "Envoy Gateway — CNCF-проект, полная конформность Gateway API, расширения через policy attachment, метрики/логи Envoy",
         "<font face='Courier'>kubectl get gateway -A</font> (PROGRAMMED=True), curl по §5 README"],
        ["4. Мониторинг",
         "kube-prometheus-stack; ServiceMonitor/PodMonitor: Envoy, nginx, Fluentd, Envoy Gateway, cert-manager, MetalLB, "
         "control plane; дашборд Grafana и PrometheusRule (SLO-алерты + recording rules)",
         "Де-факто стандарт; таргеты описаны декларативно рядом с приложением",
         "Prometheus: <font face='Courier'>sum by (job)(up)</font>; Grafana → дашборд kube-gateway-lab"],
        ["5. Логирование",
         "Fluentd DaemonSet: tail CRI-логов, kubernetes_metadata, JSON-парсинг nginx/Envoy, file buffer → OpenSearch "
         "(индексы app-demo, gateway-access, k8s-logs; шаблоны, ISM 7d, index patterns создаются автоматически)",
         "Fluentd — CNCF graduated, официальный образ с плагином OpenSearch; OpenSearch (Apache 2.0) — полнотекстовый поиск",
         "запрос <font face='Courier'>/?probe=X</font> → поиск X в app-demo-* (команды в §7 README)"],
        ["6. Ubuntu 24.04",
         "Проверка ОС в deploy.sh и playbook; e2e в CI на чистом раннере ubuntu-24.04",
         "Доказуемая воспроизводимость на целевой ОС при каждом изменении",
         "вкладка Actions → job «E2E - kubeadm cluster on Ubuntu 24.04»"],
        ["7. Автоматизация",
         "<font face='Courier'>sudo ./deploy.sh</font>: pre-flight → venv с закреплённым Ansible → site.yml → smoke-test. "
         "Идемпотентно: kubeadm только при отсутствии admin.conf, Helm-модуль сравнивает values, kubectl apply",
         "Одна команда без ручных шагов; Ansible + Helm + Kustomize — стандартный стек конфигурации",
         "повторный <font face='Courier'>sudo ./deploy.sh</font>; в CI деплой запускается дважды"],
        ["8. Документация",
         "README: архитектура (mermaid), версии, требования, установка, проверки, ограничения; этот паспорт",
         "Эксперт может пройти путь без автора", "README.md в корне"],
    ]
    s.append(table(rows, [27 * mm, 65 * mm, 45 * mm, 43 * mm]))
    s.append(Paragraph("Дополнительные улучшения", H2))
    rows = [
        ["Что реализовано", "Как технически", "Зачем", "Как проверить"],
        ["TLS + собственный PKI", "cert-manager: self-signed root → CA ClusterIssuer → wildcard *.lab.test, ротация за 15 дн.; "
                                  "ClientTrafficPolicy TLS ≥ 1.2",
         "HTTPS без ручной работы с ключами", "<font face='Courier'>sudo make ca; curl --cacert lab-ca.crt https://hello.lab.test/</font>"],
        ["Traffic splitting, маршруты по заголовку/пути/hostname", "weighted backendRefs 90/10; X-Canary; /v1, /v2 + URLRewrite; "
                                                                  "ResponseHeaderModifier; 5 hostname",
         "Канареечные релизы средствами Gateway API", "цикл из 200 запросов к /info (§5)"],
        ["Редирект HTTP→HTTPS, UI через Gateway", "RequestRedirect 301; HTTPRoute в monitoring/logging (cross-namespace)",
         "Единая точка входа", "<font face='Courier'>curl -I http://grafana.lab.test</font> → 301"],
        ["Rate limit, retry, circuit breaker", "BackendTrafficPolicy: 5 rps на /limited, 2 retry с backoff, лимиты соединений",
         "Защита backend от перегрузки", "20 быстрых запросов к /limited → 429"],
        ["Basic auth на Gateway", "SecurityPolicy + htpasswd-Secret, пароль генерируется при деплое",
         "UI без своей авторизации закрыты", "401 без пароля, 200 с паролем"],
        ["HTTP RED-метрики, дашборд и алерты как код", "Envoy upstream_rq_xx/time, nginx, CPU/RAM; tools/gen-dashboard.py; "
                                                       "9 своих алертов + recording rules",
         "Наблюдаемость по SLO", "Grafana, Prometheus → Alerts"],
        ["Поиск логов и корреляция", "OpenSearch + Dashboards, request_id в логах Envoy и nginx; ISM retention",
         "Расследование инцидентов", "OSD Discover: <font face='Courier'>uri:*probe*</font>"],
        ["Безопасность", "PSA restricted, NetworkPolicy default-deny, non-root/RO FS, без секретов в Git, sha256-pinning, gitleaks",
         "Минимальные привилегии", "<font face='Courier'>kubectl -n demo get netpol</font>"],
        ["Надёжность", "Envoy ×2 + PDB, HPA + PDB, maxUnavailable 0, preStop, probes, буферы Fluentd на диске",
         "Обновления без простоя", "<font face='Courier'>kubectl -n demo get hpa,pdb</font>"],
        ["CI/CD", "lint: yamllint, ansible-lint (production), shellcheck, helm template, kubeconform -strict по схемам из CRD "
                  "закреплённых чартов, gitleaks, trivy; e2e: kubeadm на ubuntu-24.04, повторный деплой, smoke-test",
         "Ошибки ловятся до деплоя; доказана работа на целевой ОС", "вкладка Actions, Job Summary"],
    ]
    s.append(table(rows, [34 * mm, 72 * mm, 34 * mm, 40 * mm]))
    return s


def page3():
    s = [Paragraph("3. Ревью работы и потенциальное масштабирование", H2),
         Paragraph("<b>Главная особенность.</b> Решение не только разворачивается одной командой с нуля (kubeadm, а не kind), "
                   "но и само доказывает свою работоспособность: smoke-test проверяет каждое требование — от статусов "
                   "Gateway/HTTPRoute и canary 90/10 до появления конкретного HTTP-запроса в OpenSearch и метрик в Prometheus. "
                   "Это же автоматически выполняется в CI на чистой Ubuntu 24.04 с повторным деплоем для проверки идемпотентности, "
                   "а манифесты строго валидируются по схемам CRD именно тех версий, что устанавливаются.", P),
         Spacer(1, 4),
         Paragraph("<b>Самое сложное решение.</b> Как опубликовать Gateway на bare-metal kubeadm без облачного балансировщика: "
                   "NodePort (нестандартные порты, нет адреса в status Gateway), hostNetwork для Envoy (обход модели Gateway API) "
                   "или MetalLB. Выбран MetalLB L2 с IP узла по умолчанию: Gateway получает настоящий адрес в "
                   "<font face='Courier'>status.addresses</font> и стандартные 80/443, а для multi-node пул меняется одной переменной. "
                   "Аналогично для логов OpenSearch выбран вместо Loki: он работает с официальным образом Fluentd "
                   "(для Loki нужен сторонний плагин и своя сборка образа) и даёт полнотекстовый поиск.", P),
         Spacer(1, 4),
         Paragraph("<b>Предложения по развитию</b> (и что для этого нужно):", P)]
    rows = [
        ["Направление", "Что добавить", "Что потребуется"],
        ["HA control plane", "3 control-plane узла, kube-vip/keepalived VIP, stacked или внешний etcd", "3+ ВМ, свободный VIP в сети"],
        ["GitOps", "Argo CD / Flux синхронизируют k8s/ и Helm values из Git, drift detection", "Только ресурсы кластера"],
        ["Телеком: протоколы 5G Core / IMS", "GRPCRoute для HTTP/2-сервисов 5G SBA; TCPRoute/UDPRoute (SIP, Diameter) — "
                                             "experimental-канал Gateway API, уже поддержан Envoy Gateway", "Тестовые NF (open5gs, Kamailio)"],
        ["Телеком: SLO и надёжность", "SLO 99.99% на Gateway с multi-window burn-rate алертами, синтетические пробы "
                                      "(blackbox-exporter), ретеншн метрик в Thanos/Mimir", "S3-совместимое хранилище (MinIO/Ceph)"],
        ["Телеком: data plane", "Multus + SR-IOV/DPDK для пользовательского трафика, отдельные сети управления/данных",
         "NIC с SR-IOV, CPU pinning, hugepages"],
        ["Безопасность", "OIDC вместо basic auth (SecurityPolicy oidc), mTLS между сервисами, OpenSearch security plugin, "
                         "Kyverno/Gatekeeper, подпись образов cosign", "IdP (Keycloak), PKI-политики"],
        ["Трассировка", "OpenTelemetry Collector + Tempo/Jaeger, трейсинг Envoy, exemplars в Grafana", "Ресурсы кластера"],
        ["Глобальный rate limit", "Envoy Gateway global rate limit (ratelimit + Redis) для нескольких реплик",
         "Redis (в кластере или managed)"],
        ["Air-gapped установка", "Зеркало образов и чартов (Harbor, OCI), офлайн-пакеты apt", "Внутренний registry"],
    ]
    s.append(table(rows, [36 * mm, 92 * mm, 52 * mm]))
    s.append(Spacer(1, 6))
    s.append(Paragraph("<b>Известные ограничения</b> (подробно — README §11): single-node по умолчанию (control plane не HA, "
                       "данные на local-path); MetalLB по умолчанию отдаёт IP узла (порты 80/443 должны быть свободны); "
                       "security plugin OpenSearch отключён (API только внутри кластера, UI за basic auth); metrics-server с "
                       "--kubelet-insecure-tls; локальный (не глобальный) rate limit.", SMALL))
    return s


def on_page(canvas, doc):
    canvas.saveState()
    canvas.setFont("Body", 7)
    canvas.setFillColor(MUTED)
    canvas.drawString(15 * mm, 8 * mm, f"kube-gateway-lab · {REPO}")
    canvas.drawRightString(A4[0] - 15 * mm, 8 * mm, f"стр. {doc.page}")
    canvas.restoreState()


def main():
    doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm, topMargin=12 * mm,
                            bottomMargin=14 * mm, title="Паспорт решения kube-gateway-lab", author="SharPixX",
                            subject="Kubernetes + Gateway API + Prometheus + Fluentd")
    story = page1() + [PageBreak()] + page2() + [PageBreak()] + page3()
    doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
