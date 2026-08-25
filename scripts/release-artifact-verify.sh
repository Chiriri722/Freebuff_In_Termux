#!/usr/bin/env bash
# Verify final release bytes against an independently captured digest.
set -euo pipefail

die() {
    echo "release-artifact-verify: $1" >&2
    exit 1
}

if [[ $# -ne 4 ]]; then
    die "usage: release-artifact-verify.sh <artifact> <expected-sha256> <tag> <commit>"
fi

ARTIFACT="$1"
EXPECTED_SHA256="$2"
TAG="$3"
COMMIT="$4"

[[ -f "${ARTIFACT}" ]] && [[ ! -L "${ARTIFACT}" ]] || die "artifact is missing or unsafe"
[[ "${EXPECTED_SHA256}" =~ ^[0-9a-f]{64}$ ]] || die "expected digest is malformed"
[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][[:alnum:]._-]+)?$ ]] || die "tag is malformed"
[[ "${COMMIT}" =~ ^[0-9a-f]{40}$ ]] || die "commit is malformed"

ACTUAL_SHA256="$(sha256sum "${ARTIFACT}" | awk '{print $1}')"
[[ "${ACTUAL_SHA256}" == "${EXPECTED_SHA256}" ]] || die "artifact digest changed after packaging"

ROOT_NAME="freebuff-termux-${TAG}"
mapfile -t ENTRIES < <(tar -tzf "${ARTIFACT}")
[[ ${#ENTRIES[@]} -gt 0 ]] || die "artifact is empty"
while IFS= read -r listing; do
    case "${listing:0:1}" in
        - | d) ;;
        *) die "artifact contains a link or special file" ;;
    esac
done < <(tar -tvzf "${ARTIFACT}")
for entry in "${ENTRIES[@]}"; do
    NORMALIZED_ENTRY="${entry%/}"
    [[ -n "${NORMALIZED_ENTRY}" ]] || die "artifact contains an empty path"
    [[ "${NORMALIZED_ENTRY}" == "${ROOT_NAME}" || "${NORMALIZED_ENTRY}" == "${ROOT_NAME}/"* ]] \
        || die "artifact contains a path outside its release root"
    case "${NORMALIZED_ENTRY}" in
        /* | ../* | */../* | */.. | *//* | *\\*) die "artifact contains an unsafe path" ;;
    esac
done

for required in RELEASE-METADATA package.json scripts/install.sh scripts/remote-install.sh scripts/lib/install-transaction.sh; do
    printf '%s\n' "${ENTRIES[@]}" | grep -Fxq "${ROOT_NAME}/${required}" \
        || die "artifact is missing ${required}"
done

METADATA="$(tar -xOzf "${ARTIFACT}" "${ROOT_NAME}/RELEASE-METADATA")"
metadata_value() {
    local key="$1"
    printf '%s\n' "${METADATA}" | awk -v key="${key}" \
        'index($0, key "=") == 1 { count += 1; value = substr($0, length(key) + 2) } END { if (count == 1) print value; else exit 2 }'
}
[[ "$(metadata_value schema)" == '1' ]] || die "metadata schema mismatch"
[[ "$(metadata_value tag)" == "${TAG}" ]] || die "metadata tag mismatch"
[[ "$(metadata_value commit)" == "${COMMIT}" ]] || die "metadata commit mismatch"
[[ "$(metadata_value package_version)" == "${TAG#v}" ]] || die "metadata package version mismatch"

PACKAGE_VERSION="$(
    tar -xOzf "${ARTIFACT}" "${ROOT_NAME}/package.json" \
        | node -e 'let data=""; process.stdin.setEncoding("utf8"); process.stdin.on("data", chunk => data += chunk); process.stdin.on("end", () => { const value=JSON.parse(data).version; if (typeof value !== "string") process.exit(2); process.stdout.write(value); });'
)"
[[ "${PACKAGE_VERSION}" == "${TAG#v}" ]] || die "packaged package.json version mismatch"

printf 'artifact_verification=passed\n'
printf 'artifact_sha256=%s\n' "${ACTUAL_SHA256}"
