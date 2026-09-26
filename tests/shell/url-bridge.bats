#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  BRIDGE="${REPO_ROOT}/scripts/xdg-open-bridge.sh"
}

@test "bridge writes through the guest shared-home mapping" {
  command -v proot >/dev/null 2>&1 || skip "requires Linux proot"
  local host_home="${BATS_TEST_TMPDIR}/home"
  local queue='.cache/freebuff-termux/sessions/session.safe12/login-url'
  mkdir -p "${host_home}/$(dirname "${queue}")"
  run proot -r / -b "${host_home}:/root" /bin/bash -c \
    'export FREEBUFF_URL_BRIDGE_FILE="$1"; exec /bin/bash "$2" "$3"' \
    -- "/root/${queue}" "${BRIDGE}" 'https://example.invalid/login?private=value'
  [ "${status}" -eq 0 ]
  [ "$(cat "${host_home}/${queue}")" = 'https://example.invalid/login?private=value' ]
  [ "$(stat -c %a "${host_home}/${queue}")" = 600 ]
  [[ "${output}" != *'private=value'* ]]
}

@test "bridge rejects non-http URL schemes" {
  run env -u FREEBUFF_URL_BRIDGE_FILE bash "${BRIDGE}" file:///etc/passwd

  [ "${status}" -eq 2 ]
  [[ "${output}" == *'rejected invalid login URL'* ]]
  [[ "${output}" != *'file:///etc/passwd'* ]]
}

@test "bridge hides a valid URL unless plaintext fallback is explicit" {
  run env -u FREEBUFF_URL_BRIDGE_FILE bash "${BRIDGE}" https://example.com/login

  [ "${status}" -eq 3 ]
  [[ "${output}" != *'https://example.com/login'* ]]
}

@test "bridge prints a valid URL only with explicit plaintext fallback" {
  run env -u FREEBUFF_URL_BRIDGE_FILE \
    FREEBUFF_URL_ALLOW_PLAINTEXT=1 \
    bash "${BRIDGE}" https://example.com/login

  [ "${status}" -eq 3 ]
  [[ "${output}" == *'LOGIN URL: https://example.com/login'* ]]
}

@test "bridge rejects traversal hidden inside a session path" {
  run env \
    FREEBUFF_URL_BRIDGE_FILE='/root/.cache/freebuff-termux/sessions/session.safe12/../../outside/login-url' \
    bash "${BRIDGE}" https://example.com/login

  [ "${status}" -eq 3 ]
  [[ "${output}" == *'rejected unsafe bridge path'* ]]
  [[ "${output}" != *'https://example.com/login'* ]]
}

@test "bridge rejects control characters and oversized URLs without leaking them" {
  local url
  for url in $'https://example.invalid/private\ninjected' "https://example.invalid/$(printf '%04100d' 0)"; do
    run env FREEBUFF_URL_BRIDGE_FILE=/root/.cache/freebuff-termux/sessions/session.safe12/login-url \
      bash "${BRIDGE}" "${url}"
    [ "${status}" -eq 2 ]
    [[ "${output}" != *example.invalid* ]]
  done
}
