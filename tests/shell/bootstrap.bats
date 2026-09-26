#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    FIXTURE="${BATS_TEST_TMPDIR}/source"
    STUB_BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${FIXTURE}/scripts/lib" "${FIXTURE}/skill/freebuff-hermes-integration/scripts" "${STUB_BIN}"
    for path in scripts/remote-install.sh scripts/freebuff-wrapper.sh scripts/manage.sh \
        scripts/xdg-open-bridge.sh scripts/lib/install-transaction.sh \
        skill/freebuff-hermes-integration/scripts/health_check.sh; do
        printf '# fixture\n' >"${FIXTURE}/${path}"
    done
    printf '#!/bin/bash\nprintf "%%s\\n" "$1" >"${INSTALL_CAPTURE:?}"\n' >"${FIXTURE}/scripts/install.sh"
    chmod 644 "${FIXTURE}/scripts/install.sh"
    git init -q "${FIXTURE}"
    git -C "${FIXTURE}" add .
    git -C "${FIXTURE}" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
    COMMIT="$(git -C "${FIXTURE}" rev-parse HEAD)"
    printf '#!/bin/bash\nexit 0\n' >"${STUB_BIN}/pkg"
    cat >"${STUB_BIN}/curl" <<'STUB'
#!/bin/bash
while [[ $# -gt 0 ]]; do
    if [[ "$1" == -o ]]; then cp "${FIXTURE_ARTIFACT:?}" "$2"; exit 0; fi
    shift
done
exit 99
STUB
    chmod +x "${STUB_BIN}/pkg" "${STUB_BIN}/curl"
    mkdir -p "${BATS_TEST_TMPDIR}/artifact/freebuff-termux-v1.2.3"
    cp -R "${FIXTURE}/scripts" "${FIXTURE}/skill" "${BATS_TEST_TMPDIR}/artifact/freebuff-termux-v1.2.3/"
    printf 'schema=1\ntag=v1.2.3\ncommit=%s\n' "${COMMIT}" \
        >"${BATS_TEST_TMPDIR}/artifact/freebuff-termux-v1.2.3/RELEASE-METADATA"
    ARTIFACT="${BATS_TEST_TMPDIR}/release.tar.gz"
    tar -czf "${ARTIFACT}" -C "${BATS_TEST_TMPDIR}/artifact" freebuff-termux-v1.2.3
    ARTIFACT_SHA="$(sha256sum "${ARTIFACT}" | awk '{print $1}')"
}

bootstrap() {
    env HOME="${BATS_TEST_TMPDIR}/home-${1}" XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data-${1}" \
        PREFIX=/data/data/com.termux/files/usr TMPDIR="${BATS_TEST_TMPDIR}" \
        PATH="${STUB_BIN}:${PATH}" INSTALL_CAPTURE="${BATS_TEST_TMPDIR}/called-${1}" \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://${FIXTURE}.insteadOf" \
        GIT_CONFIG_VALUE_0=https://github.com/Chiriri722/Freebuff_In_Termux.git \
        FIXTURE_ARTIFACT="${ARTIFACT}" FREEBUFF_TERMUX_REF="${2}" \
        FREEBUFF_TERMUX_EXPECTED_COMMIT="${COMMIT}" FREEBUFF_TERMUX_ARTIFACT_SHA256="${3}" \
        bash "${REPO_ROOT}/scripts/remote-install.sh" ubuntu
}

@test "bootstrap executes a nonexecutable installer from verified checkout and artifact" {
    run bootstrap checkout "${COMMIT}" ''
    [ "${status}" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/called-checkout")" = ubuntu ]
    run bootstrap artifact v1.2.3 "${ARTIFACT_SHA}"
    [ "${status}" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/called-artifact")" = ubuntu ]
}

@test "bootstrap rejects a mismatched artifact digest before invoking its installer" {
    run bootstrap tampered v1.2.3 "$(printf '%064d' 0)"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *FAILED* ]]
    [ ! -e "${BATS_TEST_TMPDIR}/called-tampered" ]
}
