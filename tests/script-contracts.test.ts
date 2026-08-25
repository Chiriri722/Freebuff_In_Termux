import { readFileSync } from 'node:fs';

const wrapper = readFileSync(
  new URL('../scripts/freebuff-wrapper.sh', import.meta.url),
  'utf8',
);
const bridge = readFileSync(
  new URL('../scripts/xdg-open-bridge.sh', import.meta.url),
  'utf8',
);
const healthCheck = readFileSync(
  new URL(
    '../skill/freebuff-hermes-integration/scripts/health_check.sh',
    import.meta.url,
  ),
  'utf8',
);
const localInstaller = readFileSync(
  new URL('../scripts/install.sh', import.meta.url),
  'utf8',
);
const remoteInstaller = readFileSync(
  new URL('../scripts/remote-install.sh', import.meta.url),
  'utf8',
);
const ciWorkflow = readFileSync(
  new URL('../.github/workflows/ci.yml', import.meta.url),
  'utf8',
);

const wrapperSources = [['canonical wrapper', wrapper]] as const;
const bridgeSources = [['canonical bridge', bridge]] as const;

describe('installed shell runtime contracts', () => {
  describe('freebuff wrapper lifecycle', () => {
    test('keeps the URL watcher alive under errexit', () => {
      expect(wrapper).not.toMatch(/\(\(\s*count\+\+\s*\)\)/);
      expect(wrapper).toContain('WRAPPER_PID=$$');
      expect(wrapper).toContain('kill -0 "${WRAPPER_PID}"');
      expect(wrapper).not.toContain('count=0');
      expect(wrapper).not.toContain('count} -lt 3600');
    });

    test('supervises FreeBuff instead of replacing the cleanup shell', () => {
      expect(wrapper).not.toMatch(/^exec\s+\$\{PROOT_LOGIN\}/m);
      expect(wrapper).toContain('FREEBUFF_PID=$!');
      expect(wrapper).toContain('wait "${FREEBUFF_PID}"');
    });

    test('forwards termination signals and reaps owned children', () => {
      expect(wrapper).toContain('forward_signal()');
      expect(wrapper).toContain("trap 'forward_signal INT' INT");
      expect(wrapper).toContain("trap 'forward_signal TERM' TERM");
      expect(wrapper).toContain('wait "${WATCHER_PID}"');
      expect(wrapper).toContain('setsid --wait');
      expect(wrapper).toContain('FREEBUFF_PGID');
      expect(wrapper).toContain("signal_freebuff_group 'KILL'");
    });

    test('reads the installed distro and requires explicit shared storage access', () => {
      expect(wrapper).toContain('DISTRO_FILE=');
      expect(wrapper).toContain('FREEBUFF_STORAGE_BIND');
      expect(wrapper).toContain('--isolated --shared-home');
      expect(wrapper).not.toContain(
        'PROOT_LOGIN="proot-distro login --user root --bind /storage/emulated/0"',
      );
    });

    test('uses only the pinned Node runtime path', () => {
      expect(wrapper).not.toContain('.bun');
      expect(wrapper).toContain(
        '/opt/freebuff-termux/current-freebuff/bin:/opt/freebuff-termux/current-node/bin',
      );
    });
  });

  describe('reproducible installer contracts', () => {
    test('uses canonical wrapper and bridge files instead of installer heredoc copies', () => {
      expect(localInstaller).not.toContain('WRAPPER_EOF');
      expect(localInstaller).not.toContain('XDG_EOF');
      expect(remoteInstaller).not.toContain('WRAPPER_EOF');
      expect(remoteInstaller).not.toContain('XDG_EOF');
      expect(localInstaller).toContain('scripts/freebuff-wrapper.sh');
      expect(localInstaller).toContain('scripts/xdg-open-bridge.sh');
    });

    test('does not upgrade the entire Termux environment', () => {
      expect(localInstaller).not.toMatch(/pkg\s+upgrade/);
      expect(remoteInstaller).not.toMatch(/pkg\s+upgrade/);
      expect(localInstaller).not.toMatch(/pkg\s+install[^\n]*\bnodejs\b/);
      expect(localInstaller).toContain('util-linux');
      expect(localInstaller).toContain('command -v setsid');
    });

    test('validates distro before deriving paths or invoking proot-distro', () => {
      expect(localInstaller).toContain('validate_identifier');
      expect(localInstaller.indexOf('validate_identifier')).toBeLessThan(
        localInstaller.indexOf('DISTRO_ROOTFS='),
      );
    });

    test('pins the default Node archives by architecture and requires a checksum for custom versions', () => {
      expect(localInstaller).toContain('dpkg --print-architecture');
      expect(localInstaller).toContain(
        'f53510706998cf044f634190416f0588e7e1937aecea938768952e0f0ac1f41b',
      );
      expect(localInstaller).toContain(
        'cfb6ac0cf339825fe36efd1f18a79016b02aca19fbfa6c9547c57e27dc09f6ea',
      );
      expect(localInstaller).toContain('FREEBUFF_NODE_TARBALL_SHA256');
      expect(localInstaller).toContain(
        'A custom Node version requires FREEBUFF_NODE_TARBALL_SHA256',
      );
      expect(localInstaller).not.toContain('SHASUMS256.txt');
      expect(localInstaller).toMatch(/sha256sum\s+-c/);
    });

    test('verifies the exact FreeBuff tarball before installing it', () => {
      expect(localInstaller).toContain('FREEBUFF_TARBALL_SHA512');
      expect(localInstaller).toContain(
        'a63c9383e94a2501cda74df90a147080c6bd60942132afdec44ebdb465b362e6847cf9786a26aec8b00b7e8b11f571c346ecad7fbf5fd98b269edf35e8393e25',
      );
      expect(localInstaller).toMatch(/sha512sum\s+-c/);
      expect(localInstaller).not.toContain('"freebuff@$version"');
    });

    test('does not replace global runtime commands inside an existing distro', () => {
      expect(localInstaller).not.toMatch(
        /ln -sfn .*\/usr\/local\/bin\/(?:node|npm|freebuff)/,
      );
      expect(localInstaller).toContain(
        '/opt/freebuff-termux/current-freebuff/bin',
      );
      expect(localInstaller).toContain('/opt/freebuff-termux/current-node/bin');
      expect(localInstaller).toContain('remove_legacy_runtime_links');
      expect(localInstaller).toContain('readlink');
    });

    test('requires explicit adoption and refuses unmanaged install targets', () => {
      expect(localInstaller).toContain('FREEBUFF_ALLOW_EXISTING_DISTRO');
      expect(localInstaller).toContain('assert_managed_target');
      expect(localInstaller).toContain('assert_runtime_link');
      expect(localInstaller).toContain('assert_runtime_root');
      expect(localInstaller).toContain('.freebuff-termux-runtime');
      expect(localInstaller).toContain('Refusing to overwrite unmanaged');
    });

    test('installs a digest-pinned PRoot image under the configured name', () => {
      expect(localInstaller).toContain('FREEBUFF_PROOT_IMAGE');
      expect(localInstaller).toMatch(/ubuntu@sha256:[0-9a-f]{64}/);
      expect(localInstaller).toMatch(/debian@sha256:[0-9a-f]{64}/);
      expect(localInstaller).toContain(
        'proot-distro install --name "${DISTRO}" "${PROOT_IMAGE}"',
      );
      expect(localInstaller).not.toContain('proot-distro install "${DISTRO}"');
    });

    test('bootstraps a validated immutable ref then delegates to the common installer', () => {
      expect(remoteInstaller).toContain('FREEBUFF_TERMUX_REF');
      expect(remoteInstaller).toContain('validate_ref');
      expect(remoteInstaller).toContain('scripts/install.sh');
      expect(remoteInstaller).not.toContain('/main/');
    });

    test('installs generated files atomically and records a manifest', () => {
      expect(localInstaller).toContain('atomic_install');
      expect(localInstaller).toContain('install-manifest');
      expect(localInstaller).toContain('install_transaction_recover');
      expect(localInstaller).toContain('login --user root --isolated');
      expect(localInstaller).toContain('schema=2');
      expect(localInstaller).toContain('proot_image=${PROOT_IMAGE}');
    });

    test('recovers a durable multi-file transaction before ownership checks', () => {
      expect(localInstaller).toContain('scripts/lib/install-transaction.sh');
      expect(localInstaller).toContain('install_transaction_recover');
      expect(localInstaller).toContain('install_transaction_begin');
      expect(localInstaller).toContain('install_transaction_commit');
      expect(localInstaller).toContain('FREEBUFF_INSTALL_TEST_FAILPOINT');
      const begin = localInstaller.indexOf('install_transaction_begin');
      const firstAsset = localInstaller.indexOf(
        'atomic_install "${REPO_ROOT}/scripts/freebuff-wrapper.sh"',
      );
      const manifest = localInstaller.indexOf(
        'atomic_install "${WORK_DIR}/install-manifest"',
      );
      const commit = localInstaller.lastIndexOf('install_transaction_commit');
      expect(begin).toBeLessThan(firstAsset);
      expect(commit).toBeGreaterThan(manifest);
    });
  });

  describe('CI shell gates', () => {
    test('runs Bash syntax, ShellCheck, and shfmt over every canonical shell entrypoint', () => {
      expect(ciWorkflow).toContain('bash -n');
      expect(ciWorkflow).toContain('shellcheck --severity=warning');
      expect(ciWorkflow).toContain('shfmt -d -i 4 -ci -bn');
      for (const path of [
        'scripts/freebuff-wrapper.sh',
        'scripts/install.sh',
        'scripts/remote-install.sh',
        'scripts/manage.sh',
        'scripts/xdg-open-bridge.sh',
        'skill/freebuff-hermes-integration/scripts/health_check.sh',
      ]) {
        expect(ciWorkflow).toContain(path);
      }
    });

    test('executes dynamic Bats contracts', () => {
      expect(ciWorkflow).toContain('bats tests/shell');
      expect(ciWorkflow).toContain('util-linux');
    });
  });

  describe('health check execution', () => {
    test('counts results without errexit-sensitive arithmetic commands', () => {
      expect(healthCheck).not.toMatch(/\(\(\s*(?:PASS|FAIL)\+\+\s*\)\)/);
      expect(healthCheck).toContain('PASS=$((PASS + 1))');
      expect(healthCheck).toContain('FAIL=$((FAIL + 1))');
    });

    test('executes checked commands as argv instead of eval strings', () => {
      expect(healthCheck).not.toContain('eval "$cmd"');
      expect(healthCheck).toContain('if "$@" >/dev/null 2>&1; then');
    });

    test('probes the same non-login shell contract as the installed wrapper', () => {
      expect(healthCheck).not.toContain('bash -lc');
      expect(healthCheck).toContain('/bin/bash');
      expect(healthCheck).toContain('--norc');
      expect(healthCheck).toContain('--noprofile');
    });

    test('checks the configured distro and pinned Node-based FreeBuff runtime', () => {
      expect(healthCheck).toContain('DISTRO_FILE=');
      expect(healthCheck).toContain('Node.js installed in distro');
      expect(healthCheck).toContain(
        '/opt/freebuff-termux/current-freebuff/bin:/opt/freebuff-termux/current-node/bin',
      );
      expect(healthCheck).not.toContain('Bun installed in distro');
      expect(healthCheck).not.toContain('--bind /storage/emulated/0');
      expect(healthCheck).toContain('list --quiet');
      expect(healthCheck).not.toContain('list --installed');
      expect(healthCheck).toContain('--isolated --shared-home');
      expect(healthCheck).not.toContain('check "npm installed"');
      expect(healthCheck).not.toContain('check "Node.js installed" command');
      expect(healthCheck).toMatch(
        /if \[\[ "\$\{FREEBUFF_STORAGE_BIND:-0\}" == "1" \]\]; then\s+check "Storage setup/,
      );
      expect(healthCheck).toContain('Memory: unavailable (unknown)');
    });
  });

  describe('session-scoped login URL bridge', () => {
    test.each(wrapperSources)(
      '%s creates and cleans a private session directory',
      (_name, source) => {
        expect(source).not.toContain('.freebuff-url-to-open');
        expect(source).toContain('umask 077');
        expect(source).toContain('BRIDGE_ROOT=');
        expect(source).toContain('SESSION_DIR="$(mktemp -d');
        expect(source).toContain('URL_BRIDGE_FILE="${SESSION_DIR}/login-url"');
        expect(source).toContain('rmdir "${SESSION_DIR}"');
      },
    );

    test.each(wrapperSources)(
      '%s validates and atomically consumes queued URLs',
      (_name, source) => {
        expect(source).toContain('is_valid_login_url()');
        expect(source).toContain('mv "${URL_BRIDGE_FILE}" "${claimed_file}"');
        expect(source).toContain('MAX_URL_LENGTH=4096');
      },
    );

    test.each(bridgeSources)(
      '%s requires the session path and atomically writes a protected file',
      (_name, source) => {
        expect(source).not.toContain('.freebuff-url-to-open');
        expect(source).toContain('URL_FILE="${FREEBUFF_URL_BRIDGE_FILE:-}"');
        expect(source).toContain('is_valid_login_url()');
        expect(source).toContain('MAX_URL_LENGTH=4096');
        expect(source).toContain('mktemp "${URL_FILE}.tmp.XXXXXX"');
        expect(source).toContain('chmod 600 "${TMP_FILE}"');
        expect(source).toContain('mv -f "${TMP_FILE}" "${URL_FILE}"');
      },
    );

    test.each(bridgeSources)(
      '%s only reveals the URL when plaintext fallback is explicitly enabled',
      (_name, source) => {
        expect(source).toContain('FREEBUFF_URL_ALLOW_PLAINTEXT');
        expect(source).not.toContain('auto-opening browser...): ${URL}');
      },
    );
  });
});
