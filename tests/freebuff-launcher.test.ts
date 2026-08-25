import { FreeBuffLauncher } from '../src/proot/freebuff-launcher.js';
import type { Spawner, SpawnResult, LaunchOptions } from '../src/types.js';

/** 테스트용 mock Spawner를 생성한다. */
const createMockSpawner = (
  results: SpawnResult[] = [],
): {
  spawner: Spawner;
  calls: { command: string; args: string[]; options?: LaunchOptions }[];
} => {
  const calls: { command: string; args: string[]; options?: LaunchOptions }[] =
    [];
  let callIndex = 0;
  return {
    calls,
    spawner: {
      async spawn(
        command: string,
        args: string[],
        options?: LaunchOptions,
      ): Promise<SpawnResult> {
        calls.push({ command, args, options });
        const result = results[callIndex++] ?? {
          exitCode: 0,
          signal: null,
          stdout: '',
          stderr: '',
        };
        return result;
      },
    },
  };
};

describe('FreeBuffLauncher', () => {
  const TERMUX_HOME = '/data/data/com.termux/files/home';
  const PROOT_HOME = '/root';
  const config = { termuxHome: TERMUX_HOME, prootHome: PROOT_HOME };

  describe('buildCommand', () => {
    test('should generate proot-distro login command with correct structure', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [cmd, args] = launcher.buildCommand(
        'ubuntu',
        '/root/my-project',
        [],
        config,
      );
      expect(cmd).toBe('proot-distro');
      expect(args[0]).toBe('login');
      expect(args).toContain('ubuntu');
      expect(args).toContain('/bin/bash');
      expect(args).toContain('--norc');
      expect(args).toContain('--noprofile');
      expect(args).toContain('-c');
      expect(args).not.toContain('-lc');
      expect(args).toContain('--isolated');
      expect(args).toContain('--shared-home');
    });

    test('should omit shared storage bind by default', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [, args] = launcher.buildCommand(
        'ubuntu',
        '/root/proj',
        [],
        config,
      );
      expect(args).not.toContain('/storage/emulated/0');
      expect(args).toContain('--isolated');
      expect(args).toContain('--shared-home');
    });

    test('should include shared storage bind when configured', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [, args] = launcher.buildCommand('ubuntu', '/root/proj', [], {
        ...config,
        storageBind: true,
      });
      expect(args).toContain('--bind');
      expect(args).toContain('/storage/emulated/0');
    });

    test('should include user flag when configured', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [, args] = launcher.buildCommand('ubuntu', '/root/proj', [], {
        ...config,
        user: 'myuser',
      });
      expect(args).toContain('--user');
      expect(args).toContain('myuser');
    });

    test('should preserve FreeBuff arguments as positional argv', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [, args] = launcher.buildCommand(
        'ubuntu',
        '/root/proj',
        [
          '--help',
          "quote'$(touch /tmp/pwn);`id`",
          'line one\nline two',
          '한글-인자',
        ],
        config,
      );
      const shellIndex = args.indexOf('-c');
      const bashCmd = args[shellIndex + 1];
      expect(bashCmd).toContain('freebuff');
      expect(bashCmd).not.toContain('/root/proj');
      expect(bashCmd).not.toContain('touch /tmp/pwn');
      expect(args.slice(shellIndex + 2)).toEqual([
        '--',
        '/root/proj',
        '--help',
        "quote'$(touch /tmp/pwn);`id`",
        'line one\nline two',
        '한글-인자',
      ]);
    });

    test('should expose the pinned Node installation paths', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [, args] = launcher.buildCommand(
        'ubuntu',
        '/root/proj',
        [],
        config,
      );
      const shellIndex = args.indexOf('-c');
      const bashCmd = args[shellIndex + 1];
      expect(bashCmd).not.toContain('BUN_INSTALL');
      expect(bashCmd).toContain(
        '/opt/freebuff-termux/current-freebuff/bin:/opt/freebuff-termux/current-node/bin:/usr/local/bin:/usr/bin:/bin',
      );
    });

    test('should reject unsafe distro and user identifiers before spawning', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      expect(() =>
        launcher.buildCommand(
          'ubuntu;touch /tmp/pwn',
          '/root/proj',
          [],
          config,
        ),
      ).toThrow(/distro/i);
      expect(() =>
        launcher.buildCommand('ubuntu', '/root/proj', [], {
          ...config,
          user: 'root --bind /',
        }),
      ).toThrow(/user/i);
    });
  });

  describe('launch', () => {
    test('should reject a failed preflight before spawning', async () => {
      const mock = createMockSpawner();
      const launcher = new FreeBuffLauncher(mock.spawner, () => ({
        ready: false,
        missing: ['freebuff'],
      }));

      await expect(
        launcher.launch('ubuntu', `${TERMUX_HOME}/proj`, [], config),
      ).rejects.toThrow(/preflight.*freebuff/i);
      expect(mock.calls).toHaveLength(0);
    });

    test('should use inherit stdio for interactive mode', async () => {
      const mock = createMockSpawner([
        { exitCode: 0, signal: null, stdout: '', stderr: '' },
      ]);
      const launcher = new FreeBuffLauncher(mock.spawner);
      await launcher.launch('ubuntu', `${TERMUX_HOME}/proj`, [], config);
      expect(mock.calls).toHaveLength(1);
      expect(mock.calls[0].options?.stdio).toBe('inherit');
    });

    test('should convert Termux CWD to proot CWD', async () => {
      const mock = createMockSpawner([
        { exitCode: 0, signal: null, stdout: '', stderr: '' },
      ]);
      const launcher = new FreeBuffLauncher(mock.spawner);
      await launcher.launch('ubuntu', `${TERMUX_HOME}/proj`, [], config);
      const shellIndex = mock.calls[0].args.indexOf('-c');
      const bashCmd = mock.calls[0].args[shellIndex + 1];
      expect(bashCmd).not.toContain('/root/proj');
      expect(mock.calls[0].args[shellIndex + 3]).toBe('/root/proj');
      expect(mock.calls[0].args).not.toContain(TERMUX_HOME);
    });
  });

  describe('run', () => {
    test('should use pipe stdio for programmatic mode', async () => {
      const mock = createMockSpawner([
        { exitCode: 0, signal: null, stdout: 'output', stderr: '' },
      ]);
      const launcher = new FreeBuffLauncher(mock.spawner);
      const result = await launcher.run(
        'ubuntu',
        `${TERMUX_HOME}/proj`,
        [],
        config,
      );
      expect(mock.calls[0].options?.stdio).toBe('pipe');
      expect(result.stdout).toBe('output');
    });

    test('should pass timeout option', async () => {
      const mock = createMockSpawner([
        { exitCode: 0, signal: null, stdout: '', stderr: '' },
      ]);
      const launcher = new FreeBuffLauncher(mock.spawner);
      await launcher.run('ubuntu', `${TERMUX_HOME}/proj`, [], config, 30000);
      expect(mock.calls[0].options?.timeout).toBe(30000);
    });

    test('should not set timeout when 0', async () => {
      const mock = createMockSpawner([
        { exitCode: 0, signal: null, stdout: '', stderr: '' },
      ]);
      const launcher = new FreeBuffLauncher(mock.spawner);
      await launcher.run('ubuntu', `${TERMUX_HOME}/proj`, [], config, 0);
      expect(mock.calls[0].options?.timeout).toBeUndefined();
    });
  });
});
