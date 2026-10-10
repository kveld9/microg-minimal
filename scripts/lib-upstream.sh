#!/usr/bin/env bash
# lib-upstream.sh - Shared helper library for microG upstream release resolution
# shellcheck shell=bash

set -euo pipefail

get_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

build_api_url() {
  local target="${1:-latest}"
  if [[ "${target}" == "latest" || "${target}" == "--latest" ]]; then
    echo "https://api.github.com/repos/microg/GmsCore/releases/latest"
    return 0
  fi
  local clean_tag="${target#--tag=}"
  echo "https://api.github.com/repos/microg/GmsCore/releases/tags/${clean_tag}"
}

fetch_release_json() {
  local api_url="$1"
  local output_file="$2"

  local -a curl_args=(
    "-sSL"
    "-w" "%{http_code}"
    "-o" "${output_file}"
    "-H" "User-Agent: curl/microg-minimal"
    "-H" "Accept: application/vnd.github+json"
  )

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=("-H" "Authorization: token ${GITHUB_TOKEN}")
  fi

  local http_code
  http_code="$(curl "${curl_args[@]}" "${api_url}")" || {
    echo "Error: Failed to connect to GitHub API at ${api_url}." >&2
    return 1
  }

  if [[ "${http_code}" != "200" ]]; then
    echo "Error: GitHub API responded with HTTP status ${http_code} for ${api_url}." >&2
    if [[ -f "${output_file}" ]] && grep -q '"message"' "${output_file}" 2>/dev/null; then
      echo "API message: $(grep '"message"' "${output_file}" | head -n 1)" >&2
    fi
    return 1
  fi
  return 0
}

parse_release_assets() {
  local json_file="$1"

  python3 -c '
import sys, json

json_path = sys.argv[1]
try:
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception as e:
    sys.stderr.write(f"Error reading JSON from {json_path}: {e}\n")
    sys.exit(1)

tag_name = data.get("tag_name", "").strip()
if not tag_name:
    sys.stderr.write("Error: Release JSON missing tag_name.\n")
    sys.exit(1)

assets = data.get("assets", [])
if not assets:
    sys.stderr.write(f"Error: Release {tag_name} has no assets.\n")
    sys.exit(1)

gms_matches = [
    a for a in assets
    if a.get("name", "").startswith("com.google.android.gms-")
    and a.get("name", "").endswith(".apk")
    and not a.get("name", "").endswith("-hw.apk")
]

vending_matches = [
    a for a in assets
    if a.get("name", "").startswith("com.android.vending-")
    and a.get("name", "").endswith(".apk")
    and not a.get("name", "").endswith("-hw.apk")
]

if len(gms_matches) != 1:
    names = [a.get("name") for a in gms_matches]
    sys.stderr.write(
        f"Error: Expected exactly 1 standard GmsCore APK asset, found {len(gms_matches)}: {names}\n"
    )
    sys.exit(1)

if len(vending_matches) != 1:
    names = [a.get("name") for a in vending_matches]
    sys.stderr.write(
        f"Error: Expected exactly 1 standard Vending APK asset, found {len(vending_matches)}: {names}\n"
    )
    sys.exit(1)

gms_asset = gms_matches[0]
vending_asset = vending_matches[0]

result = {
    "tag_name": tag_name,
    "gms_name": gms_asset.get("name"),
    "gms_url": gms_asset.get("browser_download_url"),
    "gms_size": gms_asset.get("size"),
    "vending_name": vending_asset.get("name"),
    "vending_url": vending_asset.get("browser_download_url"),
    "vending_size": vending_asset.get("size")
}

print(json.dumps(result))
' "${json_file}"
}

resolve_upstream_release() {
  local target="${1:-latest}"
  local api_url
  api_url="$(build_api_url "${target}")"

  local tmp_json
  tmp_json="$(mktemp "${TMPDIR:-/tmp}/microg-release.XXXXXX.json")"

  if ! fetch_release_json "${api_url}" "${tmp_json}"; then
    rm -f "${tmp_json}"
    return 1
  fi

  local parsed_json
  if ! parsed_json="$(parse_release_assets "${tmp_json}")"; then
    rm -f "${tmp_json}"
    return 1
  fi

  rm -f "${tmp_json}"
  echo "${parsed_json}"
  return 0
}

derive_version_info() {
  local tag="$1"
  python3 -c '
import sys, json

tag = sys.argv[1]
raw = tag.lstrip("v")
parts = raw.split(".")

# If the last part is a 6+ digit build/timestamp (e.g. 252432), strip it for base semver
if len(parts) >= 4 and len(parts[-1]) >= 6 and parts[-1].isdigit():
    semver_parts = parts[:-1]
else:
    semver_parts = parts

semver = ".".join(semver_parts)
major = int(semver_parts[0]) if len(semver_parts) > 0 and semver_parts[0].isdigit() else 0
minor = int(semver_parts[1]) if len(semver_parts) > 1 and semver_parts[1].isdigit() else 0
patch = int(semver_parts[2]) if len(semver_parts) > 2 and semver_parts[2].isdigit() else 0
subpatch = int(semver_parts[3]) if len(semver_parts) > 3 and semver_parts[3].isdigit() else 0

# VersionCode formula: (MAJOR * 100000) + (MINOR * 10000) + (PATCH * 10) + SUBPATCH
# Documented scheme: v0.3.17 -> 30170
version_code = (major * 100000) + (minor * 10000) + (patch * 10) + subpatch

result = {
    "semver": semver,
    "module_version": f"v{semver}",
    "version_code": version_code
}
print(json.dumps(result))
' "${tag}"
}

calculate_sha256() {
  local target_file="$1"
  sha256sum "${target_file}" | awk '{print $1}'
}

get_file_size() {
  local target_file="$1"
  wc -c < "${target_file}" | tr -d ' '
}

download_asset() {
  local url="$1"
  local dest_path="$2"
  local part_path="${dest_path}.part"

  echo "Downloading: ${url}"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --progress-bar --output "${part_path}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "${part_path}" "${url}"
  else
    echo "Error: Neither curl nor wget is available." >&2
    return 1
  fi
  mv "${part_path}" "${dest_path}"
}

ensure_cached_asset() {
  local cache_dir="$1"
  local url="$2"
  local asset_name="$3"
  local expected_size="$4"
  local cache_path="${cache_dir}/${asset_name}"

  mkdir -p "${cache_dir}"

  if [[ -f "${cache_path}" ]]; then
    local current_size
    current_size="$(get_file_size "${cache_path}")"
    if [[ -n "${expected_size}" && "${current_size}" == "${expected_size}" ]]; then
      echo "Cache hit for ${asset_name} (${current_size} bytes)"
      echo "${cache_path}"
      return 0
    fi
  fi

  download_asset "${url}" "${cache_path}"
  local downloaded_size
  downloaded_size="$(get_file_size "${cache_path}")"

  if [[ -n "${expected_size}" && "${downloaded_size}" != "${expected_size}" ]]; then
    rm -f "${cache_path}"
    echo "Error: Downloaded size (${downloaded_size}) does not match expected (${expected_size}) for ${asset_name}" >&2
    return 1
  fi

  echo "${cache_path}"
}

generate_checksum_files() {
  local dist_dir="$1"
  local module_version="$2"

  local checksum_file="${dist_dir}/checksums-${module_version}.txt"
  local sha256_sums="${dist_dir}/SHA256SUMS.txt"

  (
    cd "${dist_dir}"
    local zip_pattern="microg-minimal-${module_version}.zip"
    if [[ ! -f "${zip_pattern}" ]]; then
      zip_pattern="microg-minimal-*.zip"
    fi

    echo "==================================================" > "${checksum_file}"
    echo " microG Minimal ${module_version} — Integrity Hashes" >> "${checksum_file}"
    echo "==================================================" >> "${checksum_file}"
    echo "" >> "${checksum_file}"

    echo "## SHA-256" >> "${checksum_file}"
    sha256sum ${zip_pattern} >> "${checksum_file}"
    echo "" >> "${checksum_file}"

    echo "## SHA-512" >> "${checksum_file}"
    sha512sum ${zip_pattern} >> "${checksum_file}"
    echo "" >> "${checksum_file}"

    echo "## MD5" >> "${checksum_file}"
    md5sum ${zip_pattern} >> "${checksum_file}"

    sha256sum ${zip_pattern} > "${sha256_sums}"
  )
  echo "Integrity hashes written to ${checksum_file} and ${sha256_sums}"
}

apply_project_metadata_updates() {
  local repo_root="$1"
  local module_version="$2"
  local version_code="$3"
  local semver="$4"
  local target_tag="$5"
  local gms_asset="$6"
  local gms_size="$7"
  local gms_sha="$8"
  local vending_asset="$9"
  local vending_size="${10}"
  local vending_sha="${11}"
  local date_str="${12}"

  python3 -c '
import sys, os, re, json

repo_root = sys.argv[1]
module_version = sys.argv[2]
version_code = sys.argv[3]
semver = sys.argv[4]
target_tag = sys.argv[5]
gms_asset = sys.argv[6]
gms_size = sys.argv[7]
gms_sha = sys.argv[8]
vending_asset = sys.argv[9]
vending_size = sys.argv[10]
vending_sha = sys.argv[11]
date_str = sys.argv[12]

# 1. Update versions.env
env_path = os.path.join(repo_root, "versions.env")
with open(env_path, "r", encoding="utf-8") as f:
    env_lines = f.readlines()

env_updates = {
    "MODULE_VERSION": module_version,
    "MODULE_VERSION_CODE": str(version_code),
    "GMS_VERSION": semver,
    "GMS_RELEASE_TAG": target_tag,
    "VENDING_VERSION": semver,
    "VENDING_RELEASE_TAG": target_tag,
    "GMS_URL": f"https://github.com/microg/GmsCore/releases/download/${{GMS_RELEASE_TAG}}/{gms_asset}",
    "VENDING_URL": f"https://github.com/microg/GmsCore/releases/download/${{VENDING_RELEASE_TAG}}/{vending_asset}",
    "GMS_KNOWN_SIZE": str(gms_size),
    "GMS_SHA256": gms_sha,
    "VENDING_KNOWN_SIZE": str(vending_size),
    "VENDING_SHA256": vending_sha
}

new_env_lines = []
for line in env_lines:
    replaced = False
    for k, v in env_updates.items():
        if line.startswith(f"{k}="):
            new_env_lines.append(f"{k}=\"{v}\"\n")
            replaced = True
            break
    if not replaced:
        new_env_lines.append(line)

with open(env_path, "w", encoding="utf-8") as f:
    f.writelines(new_env_lines)

# 2. Update module.prop
prop_path = os.path.join(repo_root, "module.prop")
with open(prop_path, "r", encoding="utf-8") as f:
    prop_lines = f.readlines()
new_prop_lines = []
for line in prop_lines:
    if line.startswith("version="):
        new_prop_lines.append(f"version={module_version}\n")
    elif line.startswith("versionCode="):
        new_prop_lines.append(f"versionCode={version_code}\n")
    else:
        new_prop_lines.append(line)
with open(prop_path, "w", encoding="utf-8") as f:
    f.writelines(new_prop_lines)

# 3. Update update.json
json_path = os.path.join(repo_root, "update.json")
with open(json_path, "r", encoding="utf-8") as f:
    json_data = json.load(f)
json_data["version"] = module_version
json_data["versionCode"] = int(version_code)
json_data["zipUrl"] = f"https://github.com/kveld9/microg-minimal/releases/download/{module_version}/microg-minimal-{module_version}.zip"
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(json_data, f, indent=2)
    f.write("\n")

# 4. Update README.md
readme_path = os.path.join(repo_root, "README.md")
with open(readme_path, "r", encoding="utf-8") as f:
    readme_content = f.read()

gms_pattern = r"(\|\s*\*\*GmsCore\*\*\s*\|\s*`system/priv-app/GmsCoreGo/GmsCoreGo\.apk`\s*\|\s*`com\.google\.android\.gms`\s*)\([^)]*\)(\s*\|\s*)[0-9,]+(\s*\|\s*`)[a-f0-9]+(`\s*\|)"
vending_pattern = r"(\|\s*\*\*Phonesky\*\*\s*\|\s*`system/priv-app/Phonesky/Phonesky\.apk`\s*\|\s*`com\.android\.vending`\s*)\([^)]*\)(\s*\|\s*)[0-9,]+(\s*\|\s*`)[a-f0-9]+(`\s*\|)"

gms_formatted = f"{int(gms_size):,}"
vending_formatted = f"{int(vending_size):,}"

readme_content = re.sub(gms_pattern, rf"\g<1>({module_version})\g<2>{gms_formatted}\g<3>{gms_sha}\g<4>", readme_content)
readme_content = re.sub(vending_pattern, rf"\g<1>({module_version})\g<2>{vending_formatted}\g<3>{vending_sha}\g<4>", readme_content)
with open(readme_path, "w", encoding="utf-8") as f:
    f.write(readme_content)

# 5. Update CHANGELOG.md
changelog_path = os.path.join(repo_root, "CHANGELOG.md")
with open(changelog_path, "r", encoding="utf-8") as f:
    cl_content = f.read()
if f"## [{module_version}]" not in cl_content:
    entry = f"## [{module_version}] - {date_str}\n\n### Changed\n- Bump upstream microG to {target_tag} (GmsCore {gms_asset}, Phonesky {vending_asset}).\n\n"
    m = re.search(r"\n(## \[v[0-9]+[^\]]*\])", cl_content)
    if m:
        cl_content = cl_content[:m.start(1)] + entry + cl_content[m.start(1):]
    else:
        cl_content += "\n" + entry
with open(changelog_path, "w", encoding="utf-8") as f:
    f.write(cl_content)
' "${repo_root}" "${module_version}" "${version_code}" "${semver}" "${target_tag}" "${gms_asset}" "${gms_size}" "${gms_sha}" "${vending_asset}" "${vending_size}" "${vending_sha}" "${date_str}"
}

print_manual_git_steps() {
  local module_version="$1"
  local target_tag="$2"
  local branch="${3:-main}"

  echo ""
  echo "Manual Git commands to complete release:"
  echo "  git add versions.env module.prop update.json README.md CHANGELOG.md"
  echo "  git commit -m \"chore(microg): bump upstream microG to ${target_tag}\""
  echo "  git tag ${module_version}"
  echo "  git push origin ${branch}"
  echo "  git push origin ${module_version}"
}

print_publish_success() {
  local module_version="$1"
  local target_tag="$2"
  local commit_hash="$3"
  local branch="$4"
  local origin_url="$5"

  local release_url
  release_url="$(python3 -c '
import sys, re
url = sys.argv[1].strip()
tag = sys.argv[2].strip()
m = re.search(r"github\.com[:/]([^/]+)/([^/.]+?)(?:\.git)?$", url)
if m:
    print(f"https://github.com/{m.group(1)}/{m.group(2)}/releases/tag/{tag}")
else:
    print(f"{url}/releases/tag/{tag}")
' "${origin_url}" "${module_version}")"

  echo ""
  echo "=================================================="
  echo " Release Published Successfully!"
  echo "=================================================="
  echo "Module Version:   ${module_version}"
  echo "Upstream Target:  ${target_tag}"
  echo "Commit Hash:      ${commit_hash}"
  echo "Branch:           ${branch}"
  echo "Tag:              ${module_version}"
  echo "Remote:           origin (${origin_url})"
  echo "GitHub Release:   ${release_url}"
  echo ""
  echo "GitHub Actions (.github/workflows/release.yml) will package"
  echo "and publish the release archive with multi-hash checksums."
  echo "=================================================="
}

verify_git_preconditions() {
  local repo_root="$1"
  local branch="$2"
  local no_push="$3"
  local module_version="$4"
  local target_tag="$5"

  if ! git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Directory ${repo_root} is not inside a git work tree." >&2
    print_manual_git_steps "${module_version}" "${target_tag}" "${branch}"
    return 1
  fi

  if [[ -z "${branch}" || "${branch}" == "HEAD" ]]; then
    echo "Error: Unable to resolve a valid current git branch." >&2
    print_manual_git_steps "${module_version}" "${target_tag}" "main"
    return 1
  fi

  if [[ "${no_push}" -eq 0 ]] && ! git -C "${repo_root}" remote get-url origin >/dev/null 2>&1; then
    echo "Error: Git remote 'origin' is not configured." >&2
    echo "Configure remote with: git remote add origin <url>" >&2
    print_manual_git_steps "${module_version}" "${target_tag}" "${branch}"
    return 1
  fi

  return 0
}

stage_and_commit_publish() {
  local repo_root="$1"
  local target_tag="$2"

  git -C "${repo_root}" add \
    "${repo_root}/versions.env" \
    "${repo_root}/module.prop" \
    "${repo_root}/update.json" \
    "${repo_root}/README.md" \
    "${repo_root}/CHANGELOG.md"

  if git -C "${repo_root}" diff --cached --quiet; then
    echo "clean"
    return 0
  fi

  local commit_msg="chore(microg): bump upstream microG to ${target_tag}"
  if ! git -C "${repo_root}" commit -m "${commit_msg}" >/dev/null; then
    echo "Error: Failed to create git commit." >&2
    return 1
  fi

  git -C "${repo_root}" rev-parse HEAD
}

create_publish_tag() {
  local repo_root="$1"
  local module_version="$2"
  local branch="$3"
  local commit_hash="$4"

  if git -C "${repo_root}" rev-parse -q --verify "refs/tags/${module_version}" >/dev/null 2>&1; then
    echo "Error: Tag '${module_version}' already exists locally." >&2
    echo "Commit ${commit_hash} is preserved. Manual recovery required:" >&2
    echo "  git push origin ${branch}" >&2
    return 1
  fi

  if ! git -C "${repo_root}" tag "${module_version}"; then
    echo "Error: Failed to create git tag '${module_version}'." >&2
    return 1
  fi
  echo "Created release tag: ${module_version}"
}

push_publish_artifacts() {
  local repo_root="$1"
  local branch="$2"
  local module_version="$3"
  local commit_hash="$4"

  echo "Pushing branch ${branch} to origin..."
  if ! git -C "${repo_root}" push origin "${branch}"; then
    echo "Error: Failed to push branch ${branch} to origin." >&2
    echo "Local commit (${commit_hash}) and tag (${module_version}) are preserved." >&2
    echo "Retry push manually with:" >&2
    echo "  git push origin ${branch}" >&2
    echo "  git push origin ${module_version}" >&2
    return 1
  fi

  echo "Pushing tag ${module_version} to origin..."
  if ! git -C "${repo_root}" push origin "${module_version}"; then
    echo "Error: Failed to push tag ${module_version} to origin." >&2
    echo "Local commit (${commit_hash}) and tag (${module_version}) are preserved." >&2
    echo "Retry tag push manually with:" >&2
    echo "  git push origin ${module_version}" >&2
    return 1
  fi

  return 0
}

publish_release() {
  local repo_root="$1"
  local module_version="$2"
  local target_tag="$3"
  local branch="$4"
  local no_commit="${5:-0}"
  local no_push="${6:-0}"

  if [[ -z "${branch}" || "${branch}" == "HEAD" ]]; then
    branch="$(git -C "${repo_root}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
  fi

  if [[ "${no_commit}" -eq 1 ]]; then
    echo "Notice: --no-commit specified. Skipping commit and push."
    print_manual_git_steps "${module_version}" "${target_tag}" "${branch}"
    return 0
  fi

  if ! verify_git_preconditions "${repo_root}" "${branch}" "${no_push}" "${module_version}" "${target_tag}"; then
    return 1
  fi

  local commit_hash
  commit_hash="$(stage_and_commit_metadata_internal "${repo_root}" "${target_tag}")" || return 1

  if [[ "${commit_hash}" == "clean" ]]; then
    echo "Notice: No metadata changes to commit."
    return 0
  fi
  echo "Committed: ${commit_hash} (chore(microg): bump upstream microG to ${target_tag})"

  if ! create_publish_tag "${repo_root}" "${module_version}" "${branch}" "${commit_hash}"; then
    return 1
  fi

  if [[ "${no_push}" -eq 1 ]]; then
    echo "Notice: --no-push specified. Commit and tag created locally."
    echo "Manual push commands:"
    echo "  git push origin ${branch}"
    echo "  git push origin ${module_version}"
    return 0
  fi

  local origin_url
  origin_url="$(git -C "${repo_root}" remote get-url origin)"

  if ! push_publish_artifacts "${repo_root}" "${branch}" "${module_version}" "${commit_hash}"; then
    return 1
  fi

  print_publish_success "${module_version}" "${target_tag}" "${commit_hash}" "${branch}" "${origin_url}"
  return 0
}

stage_and_commit_metadata_internal() {
  stage_and_commit_publish "$1" "$2"
}

