#!/usr/bin/env bash
# Static validation of the repository (run by CI and `make lint`):
#   - yamllint for every YAML file
#   - shellcheck for every shell script
#   - ansible-lint (production profile) for the playbooks/roles
#   - kustomize build of every kustomization + kubeconform (strict) against the
#     Kubernetes schemas AND schemas generated from the CRDs of the pinned charts
#   - helm template of every chart with our values (catches wrong value keys/types)
# Tools expected on PATH: yamllint ansible-lint shellcheck kubectl|kustomize kubeconform helm python3
set -Eeuo pipefail
cd "$(dirname "$0")/.."

SCHEMAS="${SCHEMAS_DIR:-.cache/schemas}"
K8S_SCHEMA_VERSION="${K8S_SCHEMA_VERSION:-master}"
step() { printf '\n\e[1m== %s\e[0m\n' "$*"; }

versions() { python3 -c "import yaml,sys; d=yaml.safe_load(open('ansible/group_vars/all/versions.yml')); c=d['charts'][sys.argv[1]]; print(c['repo'], c['name'], c['version'])" "$1"; }

step "yamllint"
yamllint -s .

step "shellcheck"
shellcheck -x deploy.sh scripts/*.sh

if [[ "${SKIP_ANSIBLE_LINT:-0}" != "1" ]]; then
  step "ansible-lint"
  ANSIBLE_CONFIG=ansible/ansible.cfg ansible-lint --profile production ansible/site.yml ansible/reset.yml
fi

step "CRD schemas from pinned charts"
mkdir -p "$SCHEMAS"
if [[ ! -f "$SCHEMAS/.done" ]]; then
  for chart in envoy_gateway cert_manager kube_prometheus_stack metallb; do
    read -r repo name version < <(versions "$chart")
    repo_args=()
    [[ -n "$repo" && "$repo" != "None" ]] && repo_args=(--repo "$repo")
    echo "  $name $version"
    helm template crds "$name" "${repo_args[@]}" --version "$version" --include-crds \
      --set crds.enabled=true 2>/dev/null | python3 tools/crd2schema.py "$SCHEMAS"
  done
  touch "$SCHEMAS/.done"
fi

step "helm template with our values"
for chart in calico metrics_server kube_prometheus_stack metallb envoy_gateway cert_manager opensearch opensearch_dashboards; do
  read -r repo name version < <(versions "$chart")
  values="platform/${chart//_/-}.yaml"
  repo_args=()
  [[ -n "$repo" && "$repo" != "None" ]] && repo_args=(--repo "$repo")
  helm template lint "$name" "${repo_args[@]}" --version "$version" -f "$values" >/dev/null
  echo "  ok  $name $version ($values)"
done

step "kustomize build + kubeconform"
build() { if command -v kustomize >/dev/null; then kustomize build "$1"; else kubectl kustomize "$1"; fi; }
for dir in k8s/namespaces k8s/platform/local-path-storage k8s/gateway k8s/apps/hello k8s/logging k8s/observability; do
  build "$dir" | kubeconform -strict -summary -output text \
    -kubernetes-version "$K8S_SCHEMA_VERSION" \
    -schema-location default \
    -schema-location "$SCHEMAS/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
  echo "  ok  $dir"
done

step "lint passed"
