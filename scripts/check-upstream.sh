#!/usr/bin/env bash
# check-upstream.sh - Check microG upstream release status against versions.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/versions.env"

# shellcheck source=lib-upstream.sh
. "${SCRIPT_DIR}/lib-upstream.sh"

OUTPUT_JSON=0

print_usage() {
  cat <<'EOF'
Usage: check-upstream.sh [OPTIONS]

Queries GitHub API for the latest microG release and compares it with versions.env.

Options:
  --json       Output machine-readable JSON summary.
  --help, -h   Display this help message and exit.

Exit codes:
  0  Up-to-date: current version matches latest upstream release.
  2  Update available: a newer upstream release is available.
  1  Error: network failure, API rate limit, or asset pattern mismatch.
EOF
}

parse_arguments() {
  for arg in "$@"; do
    case "${arg}" in
      --json)
        OUTPUT_JSON=1
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        echo "Error: Unknown argument '${arg}'" >&2
        print_usage >&2
        exit 1
        ;;
    esac
  done
}

load_versions_file() {
  if [[ ! -f "${VERSIONS_FILE}" ]]; then
    echo "Error: versions.env not found at ${VERSIONS_FILE}" >&2
    exit 1
  fi
  # shellcheck source=../versions.env
  . "${VERSIONS_FILE}"
}

print_json_summary() {
  local current_tag="$1"
  local latest_tag="$2"
  local is_update_avail="$3"
  local release_json="$4"

  python3 -c '
import sys, json

current_tag = sys.argv[1]
latest_tag = sys.argv[2]
update_available = (sys.argv[3] == "true")
release_data = json.loads(sys.argv[4])

output = {
    "current_tag": current_tag,
    "latest_tag": latest_tag,
    "update_available": update_available,
    "gms_asset": release_data.get("gms_name"),
    "gms_url": release_data.get("gms_url"),
    "vending_asset": release_data.get("vending_name"),
    "vending_url": release_data.get("vending_url")
}

print(json.dumps(output, indent=2))
' "${current_tag}" "${latest_tag}" "${is_update_avail}" "${release_json}"
}

print_text_summary() {
  local current_tag="$1"
  local latest_tag="$2"
  local is_update="$3"
  local gms_name="$4"
  local gms_url="$5"
  local vending_name="$6"
  local vending_url="$7"

  echo "=================================================="
  echo " microG Upstream Release Check"
  echo "=================================================="
  echo "Current module tag:  ${current_tag}"
  echo "Latest upstream tag: ${latest_tag}"
  echo ""
  if [[ "${is_update}" == "true" ]]; then
    echo "Status: UPDATE AVAILABLE"
    echo ""
    echo "Resolved Upstream Assets:"
    echo "  - GmsCore:  ${gms_name}"
    echo "    URL:      ${gms_url}"
    echo "  - Phonesky: ${vending_name}"
    echo "    URL:      ${vending_url}"
    echo ""
    echo "Run './scripts/bump-microg.sh --latest' to update."
  else
    echo "Status: UP-TO-DATE"
  fi
  echo "=================================================="
}

main() {
  parse_arguments "$@"
  load_versions_file

  local current_tag="${GMS_RELEASE_TAG}"
  local release_json
  release_json="$(resolve_upstream_release "latest")" || exit 1

  local latest_tag gms_name gms_url vending_name vending_url
  latest_tag="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("tag_name"))' "${release_json}")"
  gms_name="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_name"))' "${release_json}")"
  gms_url="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("gms_url"))' "${release_json}")"
  vending_name="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_name"))' "${release_json}")"
  vending_url="$(python3 -c 'import sys, json; print(json.loads(sys.argv[1]).get("vending_url"))' "${release_json}")"

  local is_update="false"
  if [[ "${current_tag}" != "${latest_tag}" ]]; then
    is_update="true"
  fi

  if [[ "${OUTPUT_JSON}" -eq 1 ]]; then
    print_json_summary "${current_tag}" "${latest_tag}" "${is_update}" "${release_json}"
  else
    print_text_summary "${current_tag}" "${latest_tag}" "${is_update}" "${gms_name}" "${gms_url}" "${vending_name}" "${vending_url}"
  fi

  if [[ "${is_update}" == "true" ]]; then
    exit 2
  fi
  exit 0
}

main "$@"
