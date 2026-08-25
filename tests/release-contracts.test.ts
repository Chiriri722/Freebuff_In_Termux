import { readFileSync } from 'node:fs';

const read = (path: string): string =>
  readFileSync(new URL(path, import.meta.url), 'utf8');

const releaseWorkflow = read('../.github/workflows/release.yml');
const ciWorkflow = read('../.github/workflows/ci.yml');
const releasePreflight = read('../scripts/release-preflight.sh');
const remoteInstaller = read('../scripts/remote-install.sh');
const changelog = read('../CHANGELOG.md');

describe('release supply-chain contracts', () => {
  test('gates releases on version alignment and recorded Termux evidence', () => {
    expect(releasePreflight).toContain('package.json');
    expect(releaseWorkflow).toContain('GITHUB_REF_NAME');
    expect(releasePreflight).toContain('docs/termux-evidence');
    expect(releasePreflight).toContain('status: passed');
    expect(releaseWorkflow).toContain('scripts/release-preflight.sh');
    expect(releaseWorkflow).toContain('scripts/release-artifact-verify.sh');
    expect(releaseWorkflow).toContain('steps.package.outputs.artifact_sha256');
    expect(releaseWorkflow).toContain('find scripts -type f');
    expect(releaseWorkflow).not.toContain('grep -Fxq "commit: ${GITHUB_SHA}"');
  });

  test('runs all quality gates before creating checksummed artifacts', () => {
    expect(releaseWorkflow).toContain('npm run build');
    expect(releaseWorkflow).toContain('npm run lint');
    expect(releaseWorkflow).toContain('npm run format:check');
    expect(releaseWorkflow).toContain('npm pack --dry-run --json');
    expect(releaseWorkflow).toContain('npm run test:package-consumer');
    expect(releaseWorkflow).toContain('shellcheck --severity=warning');
    expect(releaseWorkflow).toContain('sha256sum');
    expect(releaseWorkflow).toContain('gh release create');
  });

  test('runs CI for pull requests and validates the npm payload', () => {
    expect(ciWorkflow).toMatch(
      /on:\r?\n(?: {2}.+\r?\n)* {2}pull_request:\r?\n/,
    );
    expect(ciWorkflow).toContain('npm pack --dry-run --json');
    expect(ciWorkflow).toContain('npm run test:package-consumer');
    expect(ciWorkflow).not.toMatch(
      /permissions:\r?\n(?: {2}.+\r?\n)* {2}pull_request:/,
    );
  });

  test('runs the full installer hard-crash recovery contract as root', () => {
    for (const workflow of [ciWorkflow, releaseWorkflow]) {
      expect(workflow).toContain('FREEBUFF_RUN_INSTALLER_INTEGRATION=1');
      expect(workflow).toContain('tests/shell/installer-integration.bats');
      expect(workflow).toMatch(/sudo\s+env/);
    }
  });

  test('pins GitHub Actions dependencies to immutable commit SHAs', () => {
    for (const workflow of [ciWorkflow, releaseWorkflow]) {
      expect(workflow).not.toMatch(/uses:\s+actions\/[^@\s]+@v\d/);
      for (const line of workflow
        .split(/\r?\n/)
        .filter((value) => value.includes('uses: actions/'))) {
        expect(line).toMatch(/@[0-9a-f]{40}(?:\s+#\s+v\d+)?$/);
      }
    }
  });

  test('requires an expected checksum for version-tag release artifacts', () => {
    expect(remoteInstaller).toContain('FREEBUFF_TERMUX_ARTIFACT_SHA256');
    expect(remoteInstaller).toContain('/releases/download/');
    expect(remoteInstaller).toMatch(/sha256sum\s+-c/);
    expect(remoteInstaller).toContain('RELEASE-METADATA');
  });

  test('publishes the verified source pointer only after installation succeeds', () => {
    const installCall = remoteInstaller.indexOf(
      '"${INSTALL_DIR}/scripts/install.sh" "${DISTRO}"',
    );
    const currentLinkCommit = remoteInstaller.indexOf(
      'mv -Tf -- "${CURRENT_TEMP}" "${CURRENT_LINK}"',
    );
    expect(installCall).toBeGreaterThan(-1);
    expect(currentLinkCommit).toBeGreaterThan(installCall);
    expect(remoteInstaller).toContain('verify_existing_source');
    expect(remoteInstaller).toContain('scripts/lib/install-transaction.sh');
  });

  test('maintains a Keep a Changelog compatible unreleased section', () => {
    expect(changelog).toContain('## [Unreleased]');
    expect(changelog).toContain('### Added');
    expect(changelog).toContain('### Security');
  });
});
