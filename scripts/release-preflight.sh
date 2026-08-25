#!/usr/bin/env bash
# Host-runnable release eligibility gate.
set -euo pipefail

die() {
    echo "release-preflight: $1" >&2
    exit 1
}

if [[ $# -ne 4 ]]; then
    die "usage: release-preflight.sh <ref-type> <tag> <tag-commit> <repo-root>"
fi

REF_TYPE="$1"
TAG="$2"
TAG_COMMIT="$3"
REPO_ROOT="$4"

[[ "${REF_TYPE}" == 'tag' ]] || die "release ref must be a tag"
[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][[:alnum:]._-]+)?$ ]] \
    || die "release tag is malformed"
[[ "${TAG_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || die "tag commit must be a full lowercase SHA"
[[ -d "${REPO_ROOT}/.git" ]] || die "repo root is not a Git checkout"

HEAD_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
[[ "${HEAD_COMMIT}" == "${TAG_COMMIT}" ]] || die "checkout HEAD does not match the tag commit"
[[ -z "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=all)" ]] \
    || die "release checkout is dirty"

PACKAGE_JSON="${REPO_ROOT}/package.json"
[[ -f "${PACKAGE_JSON}" ]] && [[ ! -L "${PACKAGE_JSON}" ]] || die "package.json is missing or unsafe"
PACKAGE_VERSION="$(node -e 'const fs=require("node:fs"); const p=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); if (typeof p.version !== "string") process.exit(2); process.stdout.write(p.version);' "${PACKAGE_JSON}")"
[[ "${TAG}" == "v${PACKAGE_VERSION}" ]] || die "tag and package version differ"

EVIDENCE_RELATIVE="docs/termux-evidence/${TAG}.md"
EVIDENCE="${REPO_ROOT}/${EVIDENCE_RELATIVE}"
[[ -f "${EVIDENCE}" ]] && [[ ! -L "${EVIDENCE}" ]] || die "Termux evidence is missing or unsafe"
[[ "$(sed -n '1p' "${EVIDENCE}")" == '---' ]] || die "evidence front matter is missing"
FRONT_MATTER_END="$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "${EVIDENCE}")"
[[ "${FRONT_MATTER_END}" =~ ^[0-9]+$ ]] && [[ ${FRONT_MATTER_END} -gt 2 ]] \
    || die "evidence front matter is not closed"
FRONT_MATTER_LAST=$((FRONT_MATTER_END - 1))

mapfile -t STATUS_LINES < <(sed -n "2,${FRONT_MATTER_LAST}p" "${EVIDENCE}" | grep '^status:' || true)
mapfile -t COMMIT_LINES < <(sed -n "2,${FRONT_MATTER_LAST}p" "${EVIDENCE}" | grep '^commit:' || true)
[[ ${#STATUS_LINES[@]} -eq 1 ]] && [[ "${STATUS_LINES[0]}" == 'status: passed' ]] \
    || die "evidence status must be exactly passed"
[[ ${#COMMIT_LINES[@]} -eq 1 ]] \
    && [[ "${COMMIT_LINES[0]}" =~ ^commit:\ ([0-9a-f]{40})$ ]] \
    || die "evidence commit must be one full lowercase SHA"
TESTED_COMMIT="${BASH_REMATCH[1]}"

git -C "${REPO_ROOT}" cat-file -e "${TESTED_COMMIT}^{commit}" 2>/dev/null \
    || die "tested commit is not present in repository history"
git -C "${REPO_ROOT}" merge-base --is-ancestor "${TESTED_COMMIT}" "${TAG_COMMIT}" \
    || die "tested commit is not an ancestor of the tag commit"

mapfile -t CHANGED_PATHS < <(
    git -C "${REPO_ROOT}" diff --name-only --diff-filter=ACDMRTUXB \
        "${TESTED_COMMIT}" "${TAG_COMMIT}"
)
[[ ${#CHANGED_PATHS[@]} -eq 1 ]] && [[ "${CHANGED_PATHS[0]}" == "${EVIDENCE_RELATIVE}" ]] \
    || die "only the exact evidence file may differ from the tested commit"

printf 'release_preflight=passed\n'
printf 'tested_commit=%s\n' "${TESTED_COMMIT}"
printf 'tag_commit=%s\n' "${TAG_COMMIT}"
printf 'evidence=%s\n' "${EVIDENCE_RELATIVE}"
