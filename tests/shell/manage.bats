#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  TEST_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${TEST_HOME}"
}

valid_install() {
  TEST_PREFIX="${BATS_TEST_TMPDIR}/prefix"
  ROOTFS="${TEST_PREFIX}/var/lib/proot-distro/containers/ubuntu/rootfs"
  MANIFEST="${TEST_HOME}/.local/share/freebuff-termux/install-manifest"
  mkdir -p "$(dirname "${MANIFEST}")" "${TEST_HOME}/.local/bin" \
    "${TEST_HOME}/.config/freebuff-termux" "${ROOTFS}/usr/local/bin" \
    "${ROOTFS}/opt/freebuff-termux/node-v22.17.1/bin" \
    "${ROOTFS}/opt/freebuff-termux/freebuff-0.0.152/bin"
  printf 'schema=2\ndistro=ubuntu\nnode_version=v22.17.1\nfreebuff_version=0.0.152\nproot_image=ubuntu@sha256:%064d\n' 0 >"${MANIFEST}"
  local key path sha
  for key in wrapper manager config bridge; do
    case "${key}" in
      wrapper) path="${TEST_HOME}/.local/bin/freebuff" ;;
      manager) path="${TEST_HOME}/.local/bin/freebuff-termux" ;;
      config) path="${TEST_HOME}/.config/freebuff-termux/distro" ;;
      bridge) path="${ROOTFS}/usr/local/bin/xdg-open" ;;
    esac
    printf '%s\n' "${key}" >"${path}"
    sha="$(sha256sum "${path}" | awk '{print $1}')"
    printf '%s_path=%s\n%s_sha256=%s\n' "${key}" "${path}" "${key}" "${sha}" >>"${MANIFEST}"
  done
  for path in node-v22.17.1/bin/node freebuff-0.0.152/bin/freebuff; do
    printf '#!/bin/sh\nexit 0\n' >"${ROOTFS}/opt/freebuff-termux/${path}"
    chmod +x "${ROOTFS}/opt/freebuff-termux/${path}"
  done
  ln -s /opt/freebuff-termux/node-v22.17.1 "${ROOTFS}/opt/freebuff-termux/current-node"
  ln -s /opt/freebuff-termux/freebuff-0.0.152 "${ROOTFS}/opt/freebuff-termux/current-freebuff"
}

run_doctor() {
  run env HOME="${TEST_HOME}" PREFIX="${TEST_PREFIX}" \
    XDG_CONFIG_HOME="${TEST_HOME}/.config" XDG_DATA_HOME="${TEST_HOME}/.local/share" \
    bash "${REPO_ROOT}/scripts/manage.sh" doctor "$@"
}

@test "doctor accepts guest-absolute active runtime links" {
  valid_install
  run_doctor --json
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"status":"ok"'* ]]
}

@test "doctor accepts relative current pointers and the npm executable symlink" {
  valid_install
  local runtime="${ROOTFS}/opt/freebuff-termux"
  ln -sfn node-v22.17.1 "${runtime}/current-node"
  ln -sfn freebuff-0.0.152 "${runtime}/current-freebuff"
  mkdir -p "${runtime}/freebuff-0.0.152/lib/node_modules/freebuff"
  mv "${runtime}/freebuff-0.0.152/bin/freebuff" "${runtime}/freebuff-0.0.152/lib/node_modules/freebuff/cli.js"
  ln -s ../lib/node_modules/freebuff/cli.js "${runtime}/freebuff-0.0.152/bin/freebuff"
  run_doctor --json
  [ "${status}" -eq 0 ]
}

@test "doctor rejects a mutable image in an otherwise complete valid manifest" {
  valid_install
  sed -i 's/^proot_image=.*/proot_image=ubuntu:latest/' "${MANIFEST}"
  for mode in --json ''; do
    run_doctor "${mode}"
    [ "${status}" -eq 2 ]
  done
}

@test "doctor rejects unsafe identifiers even when managed paths and checksums match" {
  valid_install
  for value in '--help' '..' 'bad/name'; do
    cp "${MANIFEST}" "${MANIFEST}.valid"
    sed -i "s|^node_version=.*|node_version=${value}|" "${MANIFEST}"
    printf 'node_tarball_sha256=%064d\n' 0 >>"${MANIFEST}"
    run_doctor --json
    [ "${status}" -eq 2 ]
    mv "${MANIFEST}.valid" "${MANIFEST}"
  done
}

@test "doctor degrades missing dangling wrong-version and nonlink active pointers" {
  valid_install
  local pointer kind
  for pointer in current-node current-freebuff; do
    local target="$(readlink "${ROOTFS}/opt/freebuff-termux/${pointer}")"
    for kind in missing dangling wrong-version file; do
      rm -f "${ROOTFS}/opt/freebuff-termux/${pointer}"
      case "${kind}" in
        dangling) ln -s /missing "${ROOTFS}/opt/freebuff-termux/${pointer}" ;;
        wrong-version) ln -s /opt/freebuff-termux/node-old "${ROOTFS}/opt/freebuff-termux/${pointer}" ;;
        file) printf wrong >"${ROOTFS}/opt/freebuff-termux/${pointer}" ;;
      esac
      run_doctor --json
      [ "${status}" -eq 1 ]
      [[ "${output}" == *'"status":"degraded"'* ]]
    done
    rm -f "${ROOTFS}/opt/freebuff-termux/${pointer}"
    ln -s "${target}" "${ROOTFS}/opt/freebuff-termux/${pointer}"
  done
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

@test "repair and update execute verified nonexecutable scripts with exact arguments" {
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
  chmod 644 "${source_dir}/scripts/install.sh"
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

  cat >"${source_dir}/scripts/remote-install.sh" <<'BOOTSTRAP'
#!/usr/bin/env bash
printf '%s\n' "$1" "${FREEBUFF_TERMUX_REF}" "${FREEBUFF_TERMUX_EXPECTED_COMMIT}" \
  "${FREEBUFF_TERMUX_ARTIFACT_SHA256}" >"${REPAIR_CAPTURE:?}"
BOOTSTRAP
  chmod 644 "${source_dir}/scripts/remote-install.sh"
  local bootstrap_sha="$(sha256sum "${source_dir}/scripts/remote-install.sh" | awk '{print $1}')"
  printf 'bootstrap_sha256=%s\n' "${bootstrap_sha}" >>"${state_dir}/install-manifest"
  run env HOME="${TEST_HOME}" PREFIX=/data/data/com.termux/files/usr REPAIR_CAPTURE="${capture}" \
    bash "${REPO_ROOT}/scripts/manage.sh" update v1.2.3 expected-commit expected-digest
  [ "${status}" -eq 0 ]
  [ "$(cat "${capture}")" = "$(printf '%s\n' ubuntu v1.2.3 expected-commit expected-digest)" ]

  printf '# modified\n' >>"${source_dir}/scripts/remote-install.sh"
  rm -f "${capture}"
  run env HOME="${TEST_HOME}" PREFIX=/data/data/com.termux/files/usr REPAIR_CAPTURE="${capture}" \
    bash "${REPO_ROOT}/scripts/manage.sh" update v1.2.3 expected-commit expected-digest
  [ "${status}" -eq 2 ]
  [ ! -e "${capture}" ]
}
