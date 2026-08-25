#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  BRIDGE="${REPO_ROOT}/scripts/xdg-open-bridge.sh"
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
    FREEBUFF_URL_BRIDGE_FILE='/data/data/com.termux/files/home/.cache/freebuff-termux/sessions/session.safe12/../../outside/login-url' \
    bash "${BRIDGE}" https://example.com/login

  [ "${status}" -eq 3 ]
  [[ "${output}" == *'rejected unsafe bridge path'* ]]
  [[ "${output}" != *'https://example.com/login'* ]]
}
