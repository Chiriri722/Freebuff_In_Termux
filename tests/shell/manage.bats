#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  TEST_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${TEST_HOME}"
}

@test "doctor returns redacted invalid JSON when the manifest is missing" {
  run env HOME="${TEST_HOME}" \
    PREFIX=/data/data/com.termux/files/usr \
    bash "${REPO_ROOT}/scripts/manage.sh" doctor --json

  [ "${status}" -eq 2 ]
  [[ "${output}" == \{* ]]
  [[ "${output}" == *'"schemaVersion":2'* ]]
  [[ "${output}" == *'"status":"invalid"'* ]]
  [[ "${output}" != *'[ERROR]'* ]]
  [[ "${output}" != *"${TEST_HOME}"* ]]
}

@test "doctor rejects a mutable PRoot image as strict JSON" {
  local state_dir="${TEST_HOME}/.local/share/freebuff-termux"
  mkdir -p "${state_dir}"
  printf '%s\n' \
    'schema=2' \
    'distro=ubuntu' \
    'proot_image=ubuntu:latest' \
    'node_version=v22.17.1' \
    'freebuff_version=0.0.152' \
    >"${state_dir}/install-manifest"

  run env HOME="${TEST_HOME}" \
    PREFIX=/data/data/com.termux/files/usr \
    bash "${REPO_ROOT}/scripts/manage.sh" doctor --json

  [ "${status}" -eq 2 ]
  [ "${output}" = '{"schemaVersion":2,"status":"invalid","distro":"unknown","checks":[]}' ]
}

@test "repair preserves custom runtime archive checksums" {
  local state_dir="${TEST_HOME}/.local/share/freebuff-termux"
  local source_dir="${BATS_TEST_TMPDIR}/verified-source"
  local capture="${BATS_TEST_TMPDIR}/repair-environment"
  local installer_sha
  mkdir -p "${state_dir}" "${source_dir}/scripts"
  cat >"${source_dir}/scripts/install.sh" <<'INSTALLER'
#!/usr/bin/env bash
printf '%s\n' \
  "distro=$1" \
  "node_version=${FREEBUFF_NODE_VERSION:-}" \
  "node_sha256=${FREEBUFF_NODE_TARBALL_SHA256:-}" \
  "freebuff_version=${FREEBUFF_VERSION:-}" \
  "freebuff_sha512=${FREEBUFF_TARBALL_SHA512:-}" \
  >"${REPAIR_CAPTURE:?}"
INSTALLER
  chmod +x "${source_dir}/scripts/install.sh"
  installer_sha="$(sha256sum "${source_dir}/scripts/install.sh" | awk '{print $1}')"
  cat >"${state_dir}/install-manifest" <<MANIFEST
schema=2
distro=ubuntu
proot_image=ubuntu@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
node_version=v99.1.2
node_tarball_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
freebuff_version=9.8.7
freebuff_tarball_sha512=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
source_path=${source_dir}
installer_sha256=${installer_sha}
wrapper_path=${TEST_HOME}/.local/bin/freebuff
wrapper_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
manager_path=${TEST_HOME}/.local/bin/freebuff-termux
manager_sha256=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
bridge_path=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu/rootfs/usr/local/bin/xdg-open
bridge_sha256=ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
config_path=${TEST_HOME}/.config/freebuff-termux/distro
config_sha256=1111111111111111111111111111111111111111111111111111111111111111
node_root=/opt/freebuff-termux/node-v99.1.2
freebuff_root=/opt/freebuff-termux/freebuff-9.8.7
MANIFEST

  run env HOME="${TEST_HOME}" \
    PREFIX=/data/data/com.termux/files/usr \
    REPAIR_CAPTURE="${capture}" \
    bash "${REPO_ROOT}/scripts/manage.sh" repair

  [ "${status}" -eq 0 ]
  [ "$(cat "${capture}")" = "$(printf '%s\n' \
    'distro=ubuntu' \
    'node_version=v99.1.2' \
    'node_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' \
    'freebuff_version=9.8.7' \
    'freebuff_sha512=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc')" ]
}
