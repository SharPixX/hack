#!/usr/bin/env bash
# Prints endpoints and (generated) credentials of the lab. Needs root to read
# /etc/kube-gateway-lab (credentials never leave the control-plane node).
#   sudo ./scripts/show-access.sh            (or: sudo make credentials)
set -Eeuo pipefail

DOMAIN="${LAB_DOMAIN:-lab.test}"
SECRETS_DIR="${LAB_SECRETS_DIR:-/etc/kube-gateway-lab}"
export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

GW_IP=$(kubectl -n edge get gateway public -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "<pending>")
read_secret() { [[ -r "$SECRETS_DIR/$1" ]] && cat "$SECRETS_DIR/$1" || echo "<run as root>"; }

cat <<EOF

  Gateway address : ${GW_IP}
  /etc/hosts      : ${GW_IP} hello.${DOMAIN} grafana.${DOMAIN} prometheus.${DOMAIN} alertmanager.${DOMAIN} logs.${DOMAIN}
                    (already added on the cluster node; add it on your workstation to use a browser)

  Demo app        : curl http://hello.${DOMAIN}/                    -> Hello World!
                    curl --cacert lab-ca.crt https://hello.${DOMAIN}/   (export CA: sudo make ca)
  Grafana         : https://grafana.${DOMAIN}        user: admin  password: $(read_secret grafana-admin-password)
  Prometheus      : https://prometheus.${DOMAIN}     user: admin  password: $(read_secret ui-basic-auth-password)
  Alertmanager    : https://alertmanager.${DOMAIN}   user: admin  password: (same as Prometheus)
  Logs (OSD)      : https://logs.${DOMAIN}           user: admin  password: (same as Prometheus)

  Full check      : sudo make verify
EOF
