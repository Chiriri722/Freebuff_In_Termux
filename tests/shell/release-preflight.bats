#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    PREFLIGHT="${REPO_ROOT}/scripts/release-preflight.sh"
    ARTIFACT_VERIFY="${REPO_ROOT}/scripts/release-artifact-verify.sh"
    FIXTURE="${BATS_TEST_TMPDIR}/release-fixture"
    mkdir -p "${FIXTURE}/docs/termux-evidence"
    printf '{"name":"freebuff-termux","version":"1.2.3"}\n' >"${FIXTURE}/package.json"
    printf 'runtime bytes\n' >"${FIXTURE}/runtime.txt"
    git -C "${FIXTURE}" init -q
    git -C "${FIXTURE}" config user.email test@example.invalid
    git -C "${FIXTURE}" config user.name 'Release Test'
    git -C "${FIXTURE}" add package.json runtime.txt
    git -C "${FIXTURE}" commit -qm 'tested runtime'
    TESTED_COMMIT="$(git -C "${FIXTURE}" rev-parse HEAD)"
    cat >"${FIXTURE}/docs/termux-evidence/v1.2.3.md" <<EVIDENCE
---
status: passed
commit: ${TESTED_COMMIT}
---
device evidence
EVIDENCE
    git -C "${FIXTURE}" add docs/termux-evidence/v1.2.3.md
    git -C "${FIXTURE}" commit -qm 'record device evidence'
    TAG_COMMIT="$(git -C "${FIXTURE}" rev-parse HEAD)"
}

@test "accepts an evidence-only tag commit for the exact tested runtime" {
    run bash "${PREFLIGHT}" tag v1.2.3 "${TAG_COMMIT}" "${FIXTURE}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"tested_commit=${TESTED_COMMIT}"* ]]
}

@test "rejects a branch ref and a malformed version tag" {
    run bash "${PREFLIGHT}" branch v1.2.3 "${TAG_COMMIT}" "${FIXTURE}"
    [ "${status}" -ne 0 ]

    run bash "${PREFLIGHT}" tag latest "${TAG_COMMIT}" "${FIXTURE}"
    [ "${status}" -ne 0 ]
}

@test "rejects package version or evidence commit mismatch" {
    printf '{"name":"freebuff-termux","version":"1.2.4"}\n' >"${FIXTURE}/package.json"
    git -C "${FIXTURE}" add package.json
    git -C "${FIXTURE}" commit -qm 'wrong package version'
    local wrong_version_commit
    wrong_version_commit="$(git -C "${FIXTURE}" rev-parse HEAD)"
    run bash "${PREFLIGHT}" tag v1.2.3 "${wrong_version_commit}" "${FIXTURE}"
    [ "${status}" -ne 0 ]

    git -C "${FIXTURE}" reset -q --hard "${TAG_COMMIT}"
    sed -i 's/^commit:.*/commit: 0000000000000000000000000000000000000000/' \
        "${FIXTURE}/docs/termux-evidence/v1.2.3.md"
    git -C "${FIXTURE}" add docs/termux-evidence/v1.2.3.md
    git -C "${FIXTURE}" commit -qm 'wrong evidence commit'
    local wrong_evidence_commit
    wrong_evidence_commit="$(git -C "${FIXTURE}" rev-parse HEAD)"
    run bash "${PREFLIGHT}" tag v1.2.3 "${wrong_evidence_commit}" "${FIXTURE}"
    [ "${status}" -ne 0 ]
}

@test "rejects runtime changes made after the tested commit" {
    printf 'changed after device test\n' >"${FIXTURE}/runtime.txt"
    git -C "${FIXTURE}" add runtime.txt
    git -C "${FIXTURE}" commit -qm 'change runtime after evidence'
    local changed_commit
    changed_commit="$(git -C "${FIXTURE}" rev-parse HEAD)"

    run bash "${PREFLIGHT}" tag v1.2.3 "${changed_commit}" "${FIXTURE}"
    [ "${status}" -ne 0 ]
}

@test "rejects evidence with unclosed front matter" {
    sed -i '4d' "${FIXTURE}/docs/termux-evidence/v1.2.3.md"
    git -C "${FIXTURE}" add docs/termux-evidence/v1.2.3.md
    git -C "${FIXTURE}" commit -qm 'unclosed evidence front matter'
    local malformed_commit
    malformed_commit="$(git -C "${FIXTURE}" rev-parse HEAD)"

    run bash "${PREFLIGHT}" tag v1.2.3 "${malformed_commit}" "${FIXTURE}"
    [ "${status}" -ne 0 ]
}

@test "rejects a dirty tree before release" {
    printf 'dirty\n' >>"${FIXTURE}/runtime.txt"
    run bash "${PREFLIGHT}" tag v1.2.3 "${TAG_COMMIT}" "${FIXTURE}"
    [ "${status}" -ne 0 ]
}

@test "verifies final artifact bytes against an independent expected digest" {
    local root_name="freebuff-termux-v1.2.3"
    local release_dir="${FIXTURE}/release/${root_name}"
    local artifact="${FIXTURE}/release/${root_name}.tar.gz"
    mkdir -p "${release_dir}/scripts/lib"
    cp "${FIXTURE}/package.json" "${release_dir}/package.json"
    printf 'echo ok\n' >"${release_dir}/scripts/install.sh"
    printf 'echo ok\n' >"${release_dir}/scripts/remote-install.sh"
    printf 'echo ok\n' >"${release_dir}/scripts/lib/install-transaction.sh"
    cat >"${release_dir}/RELEASE-METADATA" <<METADATA
schema=1
tag=v1.2.3
commit=${TAG_COMMIT}
package_version=1.2.3
METADATA
    tar -czf "${artifact}" -C "${FIXTURE}/release" "${root_name}"
    local expected
    expected="$(sha256sum "${artifact}" | awk '{print $1}')"

    run bash "${ARTIFACT_VERIFY}" "${artifact}" "${expected}" v1.2.3 "${TAG_COMMIT}"
    [ "${status}" -eq 0 ]

    printf 'tampered\n' >>"${artifact}"
    run bash "${ARTIFACT_VERIFY}" "${artifact}" "${expected}" v1.2.3 "${TAG_COMMIT}"
    [ "${status}" -ne 0 ]
}
