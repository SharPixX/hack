#!/usr/bin/env bash
# Static validation of the repository (run by CI and `make lint`):
#   - yamllint for every YAML file
#   - shellcheck for every shell script
#   - ansible-lint (production profile) for the playbooks/roles
#   - helm template of every chart with our values (catches wrong value keys/types)
#   - kustomize build of every kustomization + kubeconform (strict) against the
#     Kubernetes schemas AND schemas generated from the CRDs of the pinned charts
# All checks run even if one fails; the exit code is non-zero if any failed.
# Tools expected on PATH: yamllint ansible-lint shellcheck kustomize kubeconform helm python3
set -Euo pipefail
cd "$(dirname "$0")/.." || exit 1

SCHEMAS="${SCHEMAS_DIR:-.cache/schemas}"
K8S_SCHEMA_VERSION="${K8S_SCHEMA_VERSION:-master}"
FAILED=()

step() { printf '\n\e[1m== %s\e[0m\n' "$1"; }
run() {
  local name=$1
  shift
  step "$name"
  if "$@"; then echo "  ok"; else FAILED+=("$name"); echo "  FAILED: $name"; fi
}

chart() { python3 -c "import yaml,sys; c=yaml.safe_load(open('ansible/group_vars/all/versions.yml'))['charts'][sys.argv[1]]; print(c['repo'] or '-', c['name'], c['version'])" "$1"; }

helm_args() { [[ $1 == - ]] || printf -- '--repo\n%s\n' "$1"; }

crd_schemas() {
  [[ -f "$SCHEMAS/.done" ]] && return 0
  mkdir -p "$SCHEMAS"
  local c repo name version
  for c in envoy_gateway cert_manager kube_prometheus_stack metallb; do
    read -r repo name version < <(chart "$c")
    echo "  CRDs of $name $version"
    mapfile -t args < <(helm_args "$repo")
    helm template crds "$name" "${args[@]}" --version "$version" --include-crds --set crds.enabled=true \
      | python3 tools/crd2schema.py "$SCHEMAS" || return 1
  done
  touch "$SCHEMAS/.done"
}

helm_values() {
  local c repo name version rc=0
  for c in calico metrics_server kube_prometheus_stack metallb envoy_gateway cert_manager opensearch opensearch_dashboards; do
    read -r repo name version < <(chart "$c")
    mapfile -t args < <(helm_args "$repo")
    if helm template lint "$name" "${args[@]}" --version "$version" -f "platform/${c//_/-}.yaml" >/dev/null; then
      echo "  ok  $name $version"
    else
      echo "  FAIL $name $version"; rc=1
    fi
  done
  return $rc
}

kubeconform_all() {
  local dir rc=0
  for dir in k8s/namespaces k8s/platform/local-path-storage k8s/gateway k8s/apps/hello k8s/logging k8s/observability; do
    echo "  $dir"
    kustomize build "$dir" | kubeconform -strict -summary -output text \
      -kubernetes-version "$K8S_SCHEMA_VERSION" \
      -schema-location default \
      -schema-location "$SCHEMAS/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" || rc=1
  done
  return $rc
}

# Config tests inside the exact images that run in the cluster (needs Docker; CI has it)
config_tests() {
  local nginx_img fluentd_img tmp
  nginx_img=$(awk '/image: .*nginx-unprivileged/ {print $2}' k8s/apps/hello/base/deployment.yaml)
  fluentd_img=$(awk '/image: .*fluentd-kubernetes-daemonset/ {print $2}' k8s/logging/fluentd.yaml)
  tmp=$(mktemp -d)
  # shellcheck disable=SC2016 # literal nginx variable
  echo 'set $app_version "test";' >"$tmp/version.conf"
  echo "  nginx -t ($nginx_img)"
  docker run --rm -v "$PWD/k8s/apps/hello/base/nginx.conf:/etc/nginx/nginx.conf:ro" -v "$tmp:/etc/nginx/app:ro" \
    "$nginx_img" nginx -t || return 1
  echo "  fluentd --dry-run ($fluentd_img)"
  docker run --rm -e OPENSEARCH_HOST=localhost -e OPENSEARCH_PORT=9200 -e OPENSEARCH_SCHEME=http \
    -v "$PWD/k8s/logging:/fluentd/etc:ro" "$fluentd_img" \
    fluentd --dry-run -c /fluentd/etc/fluent.conf -p /fluentd/plugins || return 1
  rm -rf "$tmp"
}

run "yamllint" yamllint -s .
run "shellcheck" shellcheck -x deploy.sh scripts/*.sh
if [[ "${SKIP_ANSIBLE_LINT:-0}" != "1" ]]; then
  run "ansible-lint" env ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint --profile production ansible/site.yml ansible/reset.yml
fi
run "CRD schemas from pinned charts" crd_schemas
run "helm template with our values" helm_values
run "kustomize build + kubeconform" kubeconform_all
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  run "nginx/fluentd config tests in the deployed images" config_tests
else
  step "nginx/fluentd config tests skipped (no Docker)"
fi

if ((${#FAILED[@]})); then
  printf '\n\e[31mLint failed:\e[0m %s\n' "${FAILED[*]}"
  exit 1
fi
printf '\n\e[32mAll static checks passed\e[0m\n'
