#!/usr/bin/env python3
import json
import os
import re
import subprocess


def parse_semver(tag_str):
    raw = tag_str.lstrip("v")
    parts = raw.split(".")
    if len(parts) >= 4 and len(parts[-1]) >= 6 and parts[-1].isdigit():
        parts = parts[:-1]
    nums = [int(p) if p.isdigit() else 0 for p in parts[:3]]
    while len(nums) < 3:
        nums.append(0)
    return tuple(nums)


def is_version_only_diff(latest_t, changed_files):
    if not changed_files or not set(changed_files).issubset({"versions.env", "module.prop"}):
        return False
    content_diff_cmd = ["git", "diff", f"{latest_t}..HEAD", "--"] + changed_files
    content_diff = subprocess.check_output(content_diff_cmd, text=True)
    changed_lines = [
        line[1:].strip()
        for line in content_diff.splitlines()
        if (line.startswith("+") and not line.startswith("+++"))
        or (line.startswith("-") and not line.startswith("---"))
    ]
    if not changed_lines:
        return False
    version_pattern = re.compile(r"^(MODULE_VERSION=|MODULE_VERSION_CODE=|version=|versionCode=)")
    return all(version_pattern.match(line) for line in changed_lines)


def main():
    # 1. Read V from versions.env
    v_val = None
    with open("versions.env", "r", encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^MODULE_VERSION=["\']?([^"\']+)["\']?', line.strip())
            if m:
                v_val = m.group(1).strip()
                break
    if not v_val:
        raise SystemExit("Error: MODULE_VERSION not found in versions.env")
    v_tag = f"v{v_val.lstrip('v')}"

    # 2. Get tags and find T
    tag_out = subprocess.check_output(["git", "tag", "-l", "v*"], text=True).strip()
    raw_tags = [t.strip() for t in tag_out.splitlines() if t.strip()]
    valid_tags = []
    for t in raw_tags:
        try:
            valid_tags.append((parse_semver(t), t))
        except Exception:
            pass
    valid_tags.sort(key=lambda x: x[0])
    latest_t = valid_tags[-1][1] if valid_tags else None
    tag_names = {t[1] for t in valid_tags}
    has_v_tag = v_tag in tag_names

    skip_release = False
    is_bump = False
    target_tag = None

    if not has_v_tag or not latest_t:
        target_tag = v_tag
        print(f"V ({target_tag}) has no tag in repository. Releasing V as-is.")
    else:
        trigger_paths = [
            "customize.sh.template",
            "scripts/",
            "system/",
            "META-INF/",
            "uninstall.sh",
            "sepolicy.rule",
            "module.prop",
            "versions.env",
        ]
        diff_cmd = ["git", "diff", "--name-only", f"{latest_t}..HEAD", "--"] + trigger_paths
        diff_out = subprocess.check_output(diff_cmd, text=True).strip()
        changed_files = [line.strip() for line in diff_out.splitlines() if line.strip()]

        if not diff_out or is_version_only_diff(latest_t, changed_files):
            target_tag = latest_t
            skip_release = True
            print(f"No changes in module-code trigger set since {latest_t}. Skipping publish.")
        else:
            v_maj, v_min, v_pat = parse_semver(v_val)
            t_maj, t_min, t_pat = parse_semver(latest_t)
            if (v_maj, v_min) > (t_maj, t_min):
                next_maj, next_min, next_pat = v_maj, v_min, v_pat
            else:
                base = max((v_maj, v_min, v_pat), (t_maj, t_min, t_pat))
                next_maj, next_min, next_pat = base[0], base[1], base[2] + 1
            next_ver = f"v{next_maj}.{next_min}.{next_pat}"
            next_code = (next_maj * 100000) + (next_min * 10000) + (next_pat * 10)
            target_tag = next_ver
            is_bump = True
            print(f"Trigger set changed since {latest_t}:\n{diff_out}")
            print(f"Resolved NEXT version: {next_ver} (versionCode {next_code})")

            # In-runner override for computed NEXT
            with open("versions.env", "r", encoding="utf-8") as f:
                env_content = f.read()
            env_content = re.sub(r'MODULE_VERSION="[^"]*"', f'MODULE_VERSION="{next_ver}"', env_content)
            env_content = re.sub(r'MODULE_VERSION_CODE="[^"]*"', f'MODULE_VERSION_CODE="{next_code}"', env_content)
            with open("versions.env", "w", encoding="utf-8") as f:
                f.write(env_content)

            with open("module.prop", "r", encoding="utf-8") as f:
                prop_content = f.read()
            prop_content = re.sub(r"^version=.*$", f"version={next_ver}", prop_content, flags=re.MULTILINE)
            prop_content = re.sub(r"^versionCode=.*$", f"versionCode={next_code}", prop_content, flags=re.MULTILINE)
            with open("module.prop", "w", encoding="utf-8") as f:
                f.write(prop_content)

            with open("update.json", "r", encoding="utf-8") as f:
                up_data = json.load(f)
            up_data["version"] = next_ver
            up_data["versionCode"] = int(next_code)
            up_data["zipUrl"] = f"https://github.com/kveld9/microg-minimal/releases/download/{next_ver}/microg-minimal-{next_ver}.zip"
            with open("update.json", "w", encoding="utf-8") as f:
                json.dump(up_data, f, indent=2)
                f.write("\n")
            print(f"In-runner metadata overridden for {next_ver}.")

    # Check existing release guard
    if not skip_release:
        tag_check = subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{target_tag}"], capture_output=True)
        view_res = subprocess.run(["gh", "release", "view", target_tag], capture_output=True)
        if tag_check.returncode == 0 or view_res.returncode == 0:
            print(f"Release or tag for {target_tag} already exists. Skipping publish.")
            skip_release = True

    out_file = os.environ.get("GITHUB_OUTPUT")
    if out_file:
        with open(out_file, "a", encoding="utf-8") as f:
            f.write(f"skip_release={'true' if skip_release else 'false'}\n")
            f.write(f"tag={target_tag}\n")
            f.write(f"is_bump={'true' if is_bump else 'false'}\n")


if __name__ == "__main__":
    main()
