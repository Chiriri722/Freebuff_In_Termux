import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

type PackResult = {
  filename: string;
  files: { path: string }[];
};

const npmCli = [
  process.env.npm_execpath,
  process.env.APPDATA
    ? join(
        process.env.APPDATA,
        'npm',
        'node_modules',
        'npm',
        'bin',
        'npm-cli.js',
      )
    : undefined,
  join(dirname(process.execPath), 'node_modules', 'npm', 'bin', 'npm-cli.js'),
  join(
    dirname(dirname(process.execPath)),
    'lib',
    'node_modules',
    'npm',
    'bin',
    'npm-cli.js',
  ),
].find((candidate): candidate is string =>
  Boolean(candidate && existsSync(candidate)),
);
if (!npmCli) throw new Error('a trusted npm-cli.js could not be located');
const repoRoot = process.cwd();
const bashExecutable =
  process.platform === 'win32'
    ? 'C:/Program Files/Git/bin/bash.exe'
    : '/bin/bash';
const allowlist = JSON.parse(
  readFileSync(
    new URL('./fixtures/npm-pack-allowlist.json', import.meta.url),
    'utf8',
  ),
) as string[];

const requireSuccess = (
  label: string,
  result: ReturnType<typeof spawnSync>,
): void => {
  if (result.error || result.status !== 0) {
    throw new Error(
      `${label} failed (${String(result.status)}): ${String(result.error ?? '')}\n${String(result.stdout)}\n${String(result.stderr)}`,
    );
  }
};

const parsePackResult = (stdout: string): PackResult => {
  const match = stdout.match(/(\[\s*\{[\s\S]*\}\s*\])\s*$/);
  if (!match) throw new Error(`npm pack did not emit JSON: ${stdout}`);
  const parsed = JSON.parse(match[1]) as PackResult[];
  if (parsed.length !== 1)
    throw new Error('npm pack returned multiple results');
  return parsed[0];
};

describe('packed npm consumer', () => {
  test('installs and runs from the tgz without repository fallback', () => {
    const root = mkdtempSync(join(tmpdir(), 'freebuff-packed-consumer-'));
    const packDir = join(root, 'pack');
    const consumerDir = join(root, 'consumer');
    const cacheDir = join(root, 'npm-cache');
    mkdirSync(packDir, { recursive: true });
    mkdirSync(consumerDir, { recursive: true });

    try {
      const packed = spawnSync(
        process.execPath,
        [
          npmCli,
          'pack',
          '--json',
          '--pack-destination',
          packDir,
          '--cache',
          cacheDir,
        ],
        { cwd: repoRoot, encoding: 'utf8' },
      );
      requireSuccess('npm pack', packed);
      const result = parsePackResult(String(packed.stdout));
      expect(result.files.map(({ path }) => path).sort()).toEqual(
        [...allowlist].sort(),
      );

      const tarball = join(packDir, result.filename);
      expect(existsSync(tarball)).toBe(true);
      writeFileSync(
        join(consumerDir, 'package.json'),
        '{"name":"freebuff-consumer","private":true,"type":"module"}\n',
      );
      const installed = spawnSync(
        process.execPath,
        [
          npmCli,
          'install',
          '--ignore-scripts',
          '--no-audit',
          '--no-fund',
          '--package-lock=false',
          '--cache',
          cacheDir,
          tarball,
        ],
        { cwd: consumerDir, encoding: 'utf8' },
      );
      requireSuccess('consumer install', installed);

      const packageRoot = join(consumerDir, 'node_modules', 'freebuff-termux');
      for (const asset of [
        'scripts/install.sh',
        'scripts/remote-install.sh',
        'scripts/manage.sh',
        'scripts/freebuff-wrapper.sh',
        'scripts/xdg-open-bridge.sh',
        'scripts/lib/install-transaction.sh',
        'skill/freebuff-hermes-integration/SKILL.md',
      ]) {
        expect(existsSync(join(packageRoot, asset))).toBe(true);
      }

      const imported = spawnSync(
        process.execPath,
        [
          '--input-type=module',
          '-e',
          [
            "const resolved = import.meta.resolve('freebuff-termux');",
            "const api = await import('freebuff-termux');",
            "if (typeof api.FreeBuffLauncher !== 'function') process.exit(2);",
            "if (typeof api.ProotDistroManager !== 'function') process.exit(3);",
            'console.log(resolved);',
          ].join(' '),
        ],
        { cwd: consumerDir, encoding: 'utf8' },
      );
      requireSuccess('consumer import', imported);
      const resolvedEntry = String(imported.stdout).trim();
      expect(resolvedEntry).toContain(
        'node_modules/freebuff-termux/dist/index.js',
      );
      expect(resolvedEntry.toLowerCase()).not.toContain(
        resolve(repoRoot).replaceAll('\\', '/').toLowerCase(),
      );

      const cli = spawnSync(
        process.execPath,
        [join(packageRoot, 'dist', 'index.js')],
        { cwd: consumerDir, encoding: 'utf8' },
      );
      requireSuccess('packaged entry point', cli);
      expect(String(cli.stdout)).toContain('Freebuff Termux Conversion Layer');

      const lifecycleHome = join(consumerDir, 'lifecycle-home');
      mkdirSync(lifecycleHome, { recursive: true });
      const doctor = spawnSync(
        bashExecutable,
        [
          join(packageRoot, 'scripts', 'manage.sh').replaceAll('\\', '/'),
          'doctor',
          '--json',
        ],
        {
          cwd: consumerDir,
          encoding: 'utf8',
          env: {
            ...process.env,
            HOME: lifecycleHome.replaceAll('\\', '/'),
            PREFIX: '/data/data/com.termux/files/usr',
          },
        },
      );
      expect(doctor.error).toBeUndefined();
      expect(doctor.status).toBe(2);
      expect(doctor.stderr).toBe('');
      expect(JSON.parse(String(doctor.stdout))).toEqual({
        schemaVersion: 2,
        status: 'invalid',
        distro: 'unknown',
        checks: [],
      });
      expect(String(doctor.stdout).toLowerCase()).not.toContain(
        resolve(repoRoot).replaceAll('\\', '/').toLowerCase(),
      );
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  }, 120_000);
});
