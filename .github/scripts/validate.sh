#!/usr/bin/env bash
# Validates what Argo CD reads. Run from the repo root; needs kustomize, kubeconform and yq.
set -euo pipefail
shopt -s inherit_errexit nullglob

crd_schemas='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
image_prefix='ghcr.io/cine-org/cinema'
# Kept between local runs; delete it to refetch schemas.
schema_cache="${XDG_CACHE_HOME:-$HOME/.cache}/kubeconform"
mkdir -p "$schema_cache"
failed=0

fail() {
  echo "::error::$1" >&2
  failed=1
}

kubeconform_run() {
  kubeconform -strict -summary -ignore-missing-schemas -cache "$schema_cache" \
    -schema-location default -schema-location "$crd_schemas" "$@"
}

# Covers files kustomize never reads, such as Helm values and app.yaml.
check_yaml() {
  local file
  while IFS= read -r file; do
    yq '.' "$file" >/dev/null || fail "$file is not valid YAML."
  done < <(git ls-files '*.yaml' '*.yml')
}

check_envs() {
  local dir
  for dir in apps/*/envs/* infra/*/envs/*; do
    echo "::group::$dir"
    if [[ ! -f "$dir/kustomization.yaml" ]]; then
      fail "$dir has no kustomization.yaml."
    elif ! kustomize build "$dir" | kubeconform_run; then
      fail "$dir does not build or validate."
    fi
    echo "::endgroup::"
  done
}

check_roots() {
  local file
  for file in bootstrap/root/*.yaml; do
    kubeconform_run "$file" || fail "$file does not validate."
  done
}

# The release bot edits this image's newTag (cinema: .github/actions/ops-pr).
check_image_tags() {
  local file app tag
  for file in apps/*/envs/*/kustomization.yaml; do
    app="$(cut -d/ -f2 <<<"$file")"
    tag="$(IMAGE="$image_prefix/$app" yq '.images[] | select(.name == strenv(IMAGE)) | .newTag' "$file")"

    if [[ -z "$tag" || "$tag" == null ]]; then
      fail "$file needs image $image_prefix/$app with a newTag."
    elif [[ "$tag" == latest ]]; then
      fail "$file must pin a tag, not latest."
    fi
  done
}

check_yaml
check_envs
check_roots
check_image_tags

exit "$failed"
