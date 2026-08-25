import { createHash } from 'node:crypto';
import {
  chmodSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const managePath = new URL('../scripts/manage.sh', import.meta.url);
const manageFilesystemPath = fileURLToPath(managePath).replaceAll('\\', '/');
const installer = readFileSync(
  new URL('../scripts/install.sh', import.meta.url),
  'utf8',
);
const manage = readFileSync(managePath, 'utf8');

const sha256 = (value: string): string =>
  createHash('sha256').update(value).digest('hex');

const bashExecutable =
  process.platform === 'win32'
    ? 'C:/Program Files/Git/bin/bash.exe'
    : '/bin/bash';

describe('lifecycle manager contracts', () => {
  test('installer deploys the canonical manager and records its checksum', () => {
    expect(installer).toContain('scripts/manage.sh');
    expect(installer).toContain('manager_sha256=');
    expect(installer).toContain('manager_path=');
    expect(installer).toContain('node_tarball_sha256=${NODE_TARBALL_SHA256}');
    expect(installer).toContain(
      'freebuff_tarball_sha512=${FREEBUFF_TARBALL_SHA512}',
    );
  });

  test('supports update, repair, doctor, and uninstall without sourcing manifest', () => {
    expect(manage).toMatch(/update\)/);
    expect(manage).toMatch(/repair\)/);
    expect(manage).toMatch(/doctor\)/);
    expect(manage).toMatch(/uninstall\)/);
    expect(manage).not.toMatch(/(?:source|\.)\s+[^\n]*install-manifest/);
    expect(manage).toContain('FREEBUFF_NODE_TARBALL_SHA256=');
    expect(manage).toContain('FREEBUFF_TARBALL_SHA512=');
  });

  test('uninstall is hash-guarded and never removes the distro', () => {
    expect(manage).toContain('remove_if_managed');
    expect(manage).toContain('sha256sum');
    expect(manage).not.toMatch(/proot-distro\s+(?:remove|delete|reset)/);
  });

  test('doctor emits strict redacted JSON and a degraded exit code', () => {
    const root = mkdtempSync(join(tmpdir(), 'freebuff-lifecycle-'));
    try {
      const home = root.replaceAll('\\', '/');
      const shellHomeResult = spawnSync(
        bashExecutable,
        ['-c', 'printf %s "$HOME"'],
        { encoding: 'utf8', env: { ...process.env, HOME: home } },
      );
      const shellHome = shellHomeResult.stdout;
      const stateDir = join(root, '.local', 'share', 'freebuff-termux');
      const binDir = join(root, '.local', 'bin');
      const configDir = join(root, '.config', 'freebuff-termux');
      const wrapperPath = join(binDir, 'freebuff');
      const managerPath = join(binDir, 'freebuff-termux');
      const bridgePath =
        '/data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu/rootfs/usr/local/bin/xdg-open';
      const configPath = join(configDir, 'distro');
      mkdirSync(stateDir, { recursive: true });
      mkdirSync(binDir, { recursive: true });
      mkdirSync(configDir, { recursive: true });
      writeFileSync(wrapperPath, 'wrapper\n');
      writeFileSync(managerPath, manage);
      writeFileSync(configPath, 'ubuntu\n');
      chmodSync(managerPath, 0o755);
      writeFileSync(
        join(stateDir, 'install-manifest'),
        [
          'schema=2',
          'distro=ubuntu',
          `proot_image=ubuntu@sha256:${'a'.repeat(64)}`,
          'node_version=v22.17.1',
          'freebuff_version=0.0.152',
          `wrapper_path=${shellHome}/.local/bin/freebuff`,
          `wrapper_sha256=${sha256('wrapper\n')}`,
          `manager_path=${shellHome}/.local/bin/freebuff-termux`,
          `manager_sha256=${sha256(manage)}`,
          `bridge_path=${bridgePath.replaceAll('\\', '/')}`,
          `bridge_sha256=${sha256('bridge\n')}`,
          `config_path=${shellHome}/.config/freebuff-termux/distro`,
          `config_sha256=${sha256('ubuntu\n')}`,
          'source_commit=0000000000000000000000000000000000000000',
        ].join('\n') + '\n',
      );

      const result = spawnSync(
        bashExecutable,
        [manageFilesystemPath, 'doctor', '--json'],
        {
          encoding: 'utf8',
          env: {
            ...process.env,
            HOME: home,
            PREFIX: '/data/data/com.termux/files/usr',
          },
        },
      );
      expect(result.stderr).toBe('');
      expect(result.status).toBe(1);
      const report = JSON.parse(result.stdout) as {
        schemaVersion: number;
        status: string;
        distro: string;
        checks: { id: string; ok: boolean }[];
      };
      expect(report.schemaVersion).toBe(2);
      expect(report.status).toBe('degraded');
      expect(report.distro).toBe('ubuntu');
      expect(report.checks.length).toBeGreaterThan(3);
      expect(result.stdout).not.toContain(home);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test('uninstall rejects manifest paths outside the managed layout', () => {
    const root = mkdtempSync(join(tmpdir(), 'freebuff-lifecycle-'));
    try {
      const home = root.replaceAll('\\', '/');
      const stateDir = join(root, '.local', 'share', 'freebuff-termux');
      const victimPath = join(root, 'user-owned.txt');
      mkdirSync(stateDir, { recursive: true });
      writeFileSync(victimPath, 'preserve me\n');
      writeFileSync(
        join(stateDir, 'install-manifest'),
        [
          'schema=2',
          'distro=ubuntu',
          `proot_image=ubuntu@sha256:${'a'.repeat(64)}`,
          'node_version=v22.17.1',
          'freebuff_version=0.0.152',
          `bridge_path=${victimPath.replaceAll('\\', '/')}`,
          `bridge_sha256=${sha256('preserve me\n')}`,
          `wrapper_path=${join(root, 'missing-wrapper').replaceAll('\\', '/')}`,
          `wrapper_sha256=${'b'.repeat(64)}`,
          `manager_path=${join(root, 'missing-manager').replaceAll('\\', '/')}`,
          `manager_sha256=${'c'.repeat(64)}`,
          `config_path=${join(root, 'missing-config').replaceAll('\\', '/')}`,
          `config_sha256=${'d'.repeat(64)}`,
        ].join('\n') + '\n',
      );

      const result = spawnSync(
        bashExecutable,
        [manageFilesystemPath, 'uninstall'],
        {
          encoding: 'utf8',
          env: {
            ...process.env,
            HOME: home,
            PREFIX: '/data/data/com.termux/files/usr',
          },
        },
      );

      expect(result.status).toBe(2);
      expect(existsSync(victimPath)).toBe(true);
      expect(readFileSync(victimPath, 'utf8')).toBe('preserve me\n');
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
