#!/usr/bin/env python3
"""
Aggregate SHA256 hashes for a boot image version across however many separate
"Build Ubicloud Image" workflow runs it took to get every image type green
(the pipeline is fragile enough that a single version routinely needs several
follow-up dispatches for just the failed subset - see the runs linked in the
originating discussion), and publish them into ubicloud/ubicloud's
prog/download_boot_image.rb as a PR.

Deliberately does NOT try to trigger off "the build finished" - there is no
single such event for a given version. This is meant to be run once a human
believes every required image type has a successful run for the version in
question; it verifies that itself and refuses to open a partial PR.

Usage:
    python3 publish_boot_image_hashes.py --version 20260901.1.0 \
        --source-repo ubicloud/runner-images \
        --target-repo ubicloud/ubicloud \
        [--image-types github-ubuntu-2204-x64,github-ubuntu-2204-arm64,...] \
        [--dry-run]

Requires `gh` CLI authenticated as a single identity with read access to
--source-repo's Actions runs/logs; when run with --open-pr, that same
identity also needs push + PR-create access to --target-repo (every `gh`
call in a run of this script uses the one authenticated identity - a
GitHub App installed on both repos, or an org-scoped PAT, not the default
per-repo GITHUB_TOKEN).
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

WORKFLOW_NAME = "Build Ubicloud Image"

# SHA256 of an empty file. A job can report conclusion=success while having
# hashed a missing/empty .raw file if its build step actually failed
# (observed in run 33432830251's "upload ubuntu-22.04" job).
EMPTY_FILE_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

ECHO_LINE_RE = re.compile(
    r'echo "\[\\"(?P<image_name>[^\\]+)\\", \\"\\", \\"(?P<version>[^\\]+)\\"\] => '
)
HASH_LINE_RE = re.compile(r"^(?P<hash>[0-9a-f]{64})\s+\S+\.raw$")

IMAGE_NAME_ARCH_RE = re.compile(r"^(?P<base>.+)-(?P<arch>x64|arm64)$")

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def run_gh(args, check=True):
    result = subprocess.run(["gh"] + args, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"gh {' '.join(args)} failed: {result.stderr}")
    return result.stdout


def find_matching_runs(source_repo, version):
    """All runs of WORKFLOW_NAME whose display title mentions this version."""
    raw = run_gh([
        "run", "list", "--repo", source_repo, "--workflow", WORKFLOW_NAME,
        "--limit", "200", "--json", "databaseId,displayTitle,conclusion,status",
    ])
    runs = json.loads(raw)
    return [r for r in runs if version in r["displayTitle"]]


def extract_hashes_from_run(source_repo, run_id):
    """Returns {image_name: hash} for every successful 'upload <type>' job
    in this run. Skips jobs whose log doesn't match the expected shape
    rather than guessing - a shape mismatch means the workflow changed and
    this script needs updating, not a best-effort guess."""
    jobs_raw = run_gh(["api", f"repos/{source_repo}/actions/runs/{run_id}/jobs", "--paginate"])
    parsed = json.loads(jobs_raw)
    jobs = parsed["jobs"] if isinstance(parsed, dict) else parsed
    found = {}
    for job in jobs:
        if not job["name"].startswith("upload "):
            continue
        if job["conclusion"] != "success":
            continue
        log = run_gh(
            ["api", f"repos/{source_repo}/actions/jobs/{job['id']}/logs", "--allow-escape-sequences"],
            check=False,
        )
        log = ANSI_RE.sub("", log)
        image_name = None
        version = None
        lines = log.splitlines()
        for i, line in enumerate(lines):
            m = ECHO_LINE_RE.search(line)
            if m:
                image_name = m.group("image_name")
                version = m.group("version")
                # the hash is on one of the next few lines (after step-header noise)
                for follow in lines[i + 1 : i + 15]:
                    hm = HASH_LINE_RE.search(follow.split("Z ", 1)[-1] if "Z " in follow else follow)
                    if hm:
                        sha256 = hm.group("hash")
                        if sha256 == EMPTY_FILE_SHA256:
                            print(
                                f"  WARNING: run {run_id} job {job['name']!r} (id {job['id']}) reported "
                                f"conclusion=success but hashed an EMPTY file for {image_name} - "
                                "treating as not-actually-successful, ignoring this result",
                                file=sys.stderr,
                            )
                            break
                        found[image_name] = {
                            "hash": sha256,
                            "version": version,
                            "run_id": run_id,
                            "job_id": job["id"],
                            "job_name": job["name"],
                        }
                        break
                break
    return found


def parse_image_name(image_name):
    m = IMAGE_NAME_ARCH_RE.match(image_name)
    if not m:
        raise ValueError(f"image_name {image_name!r} doesn't end in -x64/-arm64, can't split base/arch")
    return m.group("base"), m.group("arch")


def load_expected_image_names(source_repo_path, override):
    if override:
        return set(override.split(","))
    images_json = json.loads((source_repo_path / ".github" / "images.json").read_text())
    return {entry["image_name"] for entry in images_json["include"]}


def insert_into_boot_image_sha256(file_text, base_key, arch, version, sha256):
    """Textual (not full re-parse) insertion into BOOT_IMAGE_SHA256's nested
    structure, matching the file's existing hand-maintained formatting.
    Fails loudly if the expected block shape isn't found."""
    block_re = re.compile(
        rf'("{re.escape(base_key)}"\s*=>\s*\{{.*?"{re.escape(arch)}"\s*=>\s*\{{)(.*?)(\n(\s*)\}})',
        re.DOTALL,
    )
    m = block_re.search(file_text)
    if not m:
        raise ValueError(f"could not find a {base_key!r}/{arch!r} block in BOOT_IMAGE_SHA256 to insert into")

    existing_versions_block = m.group(2)
    if f'"{version}"' in existing_versions_block:
        raise ValueError(f"{base_key}/{arch}/{version} already present - refusing to duplicate")

    indent_match = re.search(r"\n(\s+)\"", existing_versions_block)
    indent = indent_match.group(1) if indent_match else "        "
    new_line = f'{indent}"{version}" => "{sha256}",'

    new_versions_block = existing_versions_block.rstrip("\n") + "\n" + new_line
    replacement = m.group(1) + new_versions_block + m.group(3)
    return file_text[: m.start()] + replacement + file_text[m.end() :]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--source-repo", default="ubicloud/runner-images")
    ap.add_argument("--target-repo", default="ubicloud/ubicloud")
    ap.add_argument("--source-repo-path", default=".", help="local checkout of source-repo, for images.json")
    ap.add_argument("--target-file", default="prog/download_boot_image.rb", help="path within a target-repo checkout")
    ap.add_argument("--target-repo-path", required=False, help="local checkout of target-repo to edit; required unless --dry-run")
    ap.add_argument("--image-types", default=None, help="comma-separated override of expected image_names")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument(
        "--open-pr", action="store_true",
        help="commit, push a branch, and open a PR against --target-repo. Without this, "
             "the file is updated locally in --target-repo-path but left uncommitted.",
    )
    args = ap.parse_args()

    runs = find_matching_runs(args.source_repo, args.version)
    if not runs:
        print(f"No runs of '{WORKFLOW_NAME}' mention version {args.version}", file=sys.stderr)
        sys.exit(1)

    # Runs aren't filtered by overall conclusion - a full-matrix run often
    # has some legs fail and others succeed; extract_hashes_from_run already
    # filters to successful "upload <type>" jobs. Two runs disagreeing on a
    # hash for the same image_name is a hard error, not resolved by picking
    # whichever run was processed last.
    combined = {}
    for r in runs:
        found = extract_hashes_from_run(args.source_repo, r["databaseId"])
        for image_name, info in found.items():
            existing = combined.get(image_name)
            if existing and existing["hash"] != info["hash"]:
                print(
                    f"CONFLICT for {image_name}: run {existing['run_id']} job "
                    f"{existing['job_name']!r} says {existing['hash']}, but run "
                    f"{info['run_id']} job {info['job_name']!r} says {info['hash']}. "
                    "Refusing to guess which is correct - investigate manually.",
                    file=sys.stderr,
                )
                sys.exit(3)
            combined[image_name] = info

    expected = load_expected_image_names(Path(args.source_repo_path), args.image_types)
    missing = expected - combined.keys()
    if missing:
        print(f"Version {args.version} is not fully published yet. Missing successful upload for:")
        for name in sorted(missing):
            print(f"  - {name}")
        sys.exit(1)

    print(f"All {len(expected)} expected image types have a successful hash for {args.version}:")
    for name in sorted(combined):
        print(f"  {name} -> {combined[name]['hash']}")

    if args.dry_run:
        print("\n--dry-run: not touching any file.")
        return

    if not args.target_repo_path:
        print("--target-repo-path is required unless --dry-run", file=sys.stderr)
        sys.exit(2)

    target_file = Path(args.target_repo_path) / args.target_file
    text = target_file.read_text()
    for image_name, info in combined.items():
        base_key, arch = parse_image_name(image_name)
        text = insert_into_boot_image_sha256(text, base_key, arch, args.version, info["hash"])
    target_file.write_text(text)
    print(f"\nUpdated {target_file}")

    if not args.open_pr:
        print("(--open-pr not passed - leaving the change uncommitted locally for review)")
        return

    branch = f"automate/boot-image-sha256-{args.version}"
    run_git(args.target_repo_path, ["checkout", "-b", branch])
    run_git(args.target_repo_path, ["add", args.target_file])
    commit_body_lines = "\n".join(
        f"- {name}: run https://github.com/{args.source_repo}/actions/runs/{info['run_id']}, "
        f"job {info['job_name']!r}"
        for name, info in sorted(combined.items())
    )
    commit_message = (
        f"Add BOOT_IMAGE_SHA256 entries for {args.version}\n\n"
        f"Aggregated from {len({i['run_id'] for i in combined.values()})} "
        f"{args.source_repo} workflow run(s):\n{commit_body_lines}\n\n"
        "Generated by scripts/publish_boot_image_hashes.py - verify before merging.\n\n"
        "Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
    )
    run_git(args.target_repo_path, ["commit", "-m", commit_message])
    run_git(args.target_repo_path, ["push", "-u", "origin", branch])

    pr_body = (
        f"Automated boot image SHA256 publish for `{args.version}`.\n\n"
        f"Aggregated from these `{args.source_repo}` workflow runs:\n\n{commit_body_lines}\n\n"
        "Please verify the hashes before merging - this was generated by "
        "`scripts/publish_boot_image_hashes.py`, not hand-transcribed.\n\n"
        "\U0001f916 Generated with [Claude Code](https://claude.com/claude-code)"
    )
    run_gh([
        "pr", "create", "--repo", args.target_repo,
        "--head", branch,
        "--title", f"Add BOOT_IMAGE_SHA256 entries for {args.version}",
        "--body", pr_body,
    ])
    print(f"\nOpened PR against {args.target_repo}")


def run_git(repo_path, args):
    result = subprocess.run(["git"] + args, cwd=repo_path, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} (in {repo_path}) failed: {result.stderr}")
    return result.stdout


if __name__ == "__main__":
    main()
