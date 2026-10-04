#!/usr/bin/env bash
# kube-gateway-lab: one-command deployment on Ubuntu 24.04.
#
#   git clone https://github.com/SharPixX/hack.git && cd hack
#   sudo ./deploy.sh
#
# What it does (idempotent, safe to re-run):
#   1. pre-flight checks (OS, CPU/RAM/disk, ports)
#   2. installs the pinned Ansible toolchain into ./.venv (no system-wide pip)
#   3. runs ansible/site.yml: kubeadm cluster + platform + demo app
#   4. runs scripts/smoke-test.sh (end-to-end verification)
#
# Environment variables:
#   INVENTORY=ansible/inventory/multinode.ini   use your own inventory (default: local single node)
#   SKIP_VERIFY=1                               do not run the smoke test at the end
#   ALLOW_UNSUPPORTED_OS=1                      skip the Ubuntu 24.04 check
#   ANSIBLE_ARGS="--tags platform -v"           extra ansible-playbook arguments
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${INVENTORY:-ansible/inventory/local.ini}"
VENV="${REPO_ROOT}/.venv"
MIN_CPU=2
MIN_MEM_MB=7000
MIN_DISK_GB=25

log()  { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33mWARN:\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
trap 'die "deployment failed at line $LINENO (see output above). Re-run is safe: sudo ./deploy.sh"' ERR

preflight() {
  [[ $EUID -eq 0 ]] || die "run as root: sudo ./deploy.sh"
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    [[ "${ALLOW_UNSUPPORTED_OS:-0}" == "1" ]] || die "tested on Ubuntu 24.04 only (found ${PRETTY_NAME:-unknown}); set ALLOW_UNSUPPORTED_OS=1 to try anyway"
    warn "unsupported OS ${PRETTY_NAME:-unknown}, continuing because ALLOW_UNSUPPORTED_OS=1"
  fi
  if [[ "$INVENTORY" == "ansible/inventory/local.ini" ]]; then
    local cpu mem disk
    cpu=$(nproc)
    mem=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    disk=$(df -BG --output=avail /var | tail -1 | tr -dc '0-9')
    log "host: ${PRETTY_NAME}, ${cpu} vCPU, ${mem} MiB RAM, ${disk} GiB free on /var"
    ((cpu >= MIN_CPU)) || die "need at least ${MIN_CPU} vCPU (4 recommended)"
    ((mem >= MIN_MEM_MB)) || warn "less than 8 GiB RAM: OpenSearch/Prometheus may be OOM-killed (8 GiB recommended)"
    ((disk >= MIN_DISK_GB)) || warn "less than ${MIN_DISK_GB} GiB free on /var"
    if [[ ! -f /etc/kubernetes/admin.conf ]]; then
      local port
      for port in 80 443 6443 10250; do
        if ss -Hltn "sport = :${port}" | grep -q .; then
          die "TCP port ${port} is already in use on this host (needed by the cluster/Gateway)"
        fi
      done
    fi
  fi
}

toolchain() {
  log "installing deployment toolchain (python venv + pinned ansible-core + collections)"
  if ! command -v python3 >/dev/null || ! python3 -c 'import venv, ensurepip' 2>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv python3-pip >/dev/null
  fi
  [[ -x "${VENV}/bin/ansible-playbook" ]] || python3 -m venv "${VENV}"
  export ANSIBLE_COLLECTIONS_PATH="${REPO_ROOT}/.ansible/collections"
  "${VENV}/bin/pip" install --quiet --disable-pip-version-check -r "${REPO_ROOT}/requirements.txt"
  "${VENV}/bin/ansible-galaxy" collection install --upgrade -r "${REPO_ROOT}/ansible/requirements.yml" \
    -p "${REPO_ROOT}/.ansible/collections" >/dev/null
}

run_playbook() {
  log "running ansible/site.yml (inventory: ${INVENTORY})"
  export ANSIBLE_CONFIG="${REPO_ROOT}/ansible/ansible.cfg"
  export ANSIBLE_COLLECTIONS_PATH="${REPO_ROOT}/.ansible/collections"
  export PATH="${VENV}/bin:${PATH}"
  # shellcheck disable=SC2086
  ansible-playbook -i "${REPO_ROOT}/${INVENTORY}" "${REPO_ROOT}/ansible/site.yml" ${ANSIBLE_ARGS:-}
}

verify() {
  if [[ "${SKIP_VERIFY:-0}" == "1" ]]; then
    log "SKIP_VERIFY=1, skipping smoke test (run later: sudo make verify)"
    return
  fi
  log "running end-to-end smoke test"
  "${REPO_ROOT}/scripts/smoke-test.sh"
}

main() {
  local start=$SECONDS
  cd "${REPO_ROOT}"
  preflight
  toolchain
  run_playbook
  verify
  log "done in $(((SECONDS - start) / 60))m$(((SECONDS - start) % 60))s"
  "${REPO_ROOT}/scripts/show-access.sh" || true
}

main "$@"
