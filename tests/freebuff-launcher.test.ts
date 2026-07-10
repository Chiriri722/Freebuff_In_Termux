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
      expect(args).toContain('bash');
      expect(args).toContain('-lc');
    });

    test('should include bind mount args', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [, args] = launcher.buildCommand(
        'ubuntu',
        '/root/proj',
        [],
        config,
      );
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

    test('should include freebuff args in bash command', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [, args] = launcher.buildCommand(
        'ubuntu',
        '/root/proj',
        ['--help'],
        config,
      );
      const bashCmd = args[args.length - 1];
      expect(bashCmd).toContain('freebuff');
      expect(bashCmd).toContain("'--help'");
    });

    test('should set BUN_INSTALL and PATH in bash command', () => {
      const launcher = new FreeBuffLauncher(createMockSpawner().spawner);
      const [, args] = launcher.buildCommand(
        'ubuntu',
        '/root/proj',
        [],
        config,
      );
      const bashCmd = args[args.length - 1];
      expect(bashCmd).toContain('BUN_INSTALL');
      expect(bashCmd).toContain('$BUN_INSTALL/bin:$PATH');
    });
  });

  describe('launch', () => {
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
      const bashCmd = mock.calls[0].args[mock.calls[0].args.length - 1];
      expect(bashCmd).toContain('/root/proj');
      expect(bashCmd).not.toContain(TERMUX_HOME);
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
