import { ProotDistroManager } from '../src/proot/proot-wrapper.js';
import type { CommandRunner, ExecResult } from '../src/types.js';

/** 테스트용 mock CommandRunner를 생성한다. */
const createMockRunner = (
  responses: { pattern: string | RegExp; result: ExecResult }[],
): CommandRunner & {
  fileCalls: { command: string; args: string[] }[];
  execCalls: string[];
} => {
  const fileCalls: { command: string; args: string[] }[] = [];
  const execCalls: string[] = [];
  const resolve = (command: string): ExecResult => {
    for (const { pattern, result } of responses) {
      if (typeof pattern === 'string') {
        if (command.includes(pattern)) return result;
      } else {
        if (pattern.test(command)) return result;
      }
    }
    return { stdout: '', stderr: 'No mock match', exitCode: 127 };
  };

  return {
    fileCalls,
    execCalls,
    exec(command: string): ExecResult {
      execCalls.push(command);
      return resolve(command);
    },
    execFile(command: string, args: string[]): ExecResult {
      fileCalls.push({ command, args });
      return resolve(`${command} ${args.join(' ')}`);
    },
  };
};

describe('ProotDistroManager', () => {
  describe('isProotDistroInstalled', () => {
    test('should return true when proot-distro command exists', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
      ]);
      expect(new ProotDistroManager(runner).isProotDistroInstalled()).toBe(
        true,
      );
      expect(runner.fileCalls).toEqual([
        { command: 'proot-distro', args: ['--help'] },
      ]);
      expect(runner.execCalls).toHaveLength(0);
    });

    test('should return false when proot-distro not found', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: { stdout: '', stderr: 'not found', exitCode: 1 },
        },
      ]);
      expect(new ProotDistroManager(runner).isProotDistroInstalled()).toBe(
        false,
      );
    });
  });

  describe('isDistroInstalled', () => {
    test('should return true when distro is in installed list', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --quiet',
          result: { stdout: 'ubuntu\n', stderr: '', exitCode: 0 },
        },
      ]);
      expect(new ProotDistroManager(runner).isDistroInstalled('ubuntu')).toBe(
        true,
      );
    });

    test('should return false when distro is not installed', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --quiet',
          result: { stdout: '', stderr: '', exitCode: 1 },
        },
      ]);
      expect(new ProotDistroManager(runner).isDistroInstalled('debian')).toBe(
        false,
      );
    });
  });

  describe('getInstalledDistros', () => {
    test('should return array of distro names', () => {
      const runner = createMockRunner([
        {
          pattern: 'list --quiet',
          result: { stdout: 'ubuntu\ndebian\n', stderr: '', exitCode: 0 },
        },
      ]);
      expect(new ProotDistroManager(runner).getInstalledDistros()).toEqual([
        'ubuntu',
        'debian',
      ]);
    });

    test('should return empty array on failure', () => {
      const runner = createMockRunner([
        {
          pattern: 'list --quiet',
          result: { stdout: '', stderr: 'error', exitCode: 1 },
        },
      ]);
      expect(new ProotDistroManager(runner).getInstalledDistros()).toEqual([]);
    });
  });

  describe('installDistro', () => {
    test('should return error when proot-distro not installed', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: { stdout: '', stderr: '', exitCode: 1 },
        },
      ]);
      const result = new ProotDistroManager(runner).installDistro('ubuntu');
      expect(result.exitCode).toBe(1);
      expect(result.stderr).toContain('proot-distro is not installed');
    });

    test('should skip when distro already installed', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --quiet',
          result: { stdout: 'ubuntu\n', stderr: '', exitCode: 0 },
        },
      ]);
      const result = new ProotDistroManager(runner).installDistro('ubuntu');
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain('already installed');
    });

    test('requires a digest-pinned image for a new distro', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --quiet',
          result: { stdout: '', stderr: '', exitCode: 0 },
        },
      ]);
      const manager = new ProotDistroManager(runner);

      const result = manager.installDistro('ubuntu');

      expect(result.exitCode).toBe(1);
      expect(result.stderr).toMatch(/digest-pinned image/i);
      expect(runner.fileCalls.some(({ args }) => args[0] === 'install')).toBe(
        false,
      );
    });

    test('installs an explicitly digest-pinned image with a safe local name', () => {
      const image = `ubuntu@sha256:${'a'.repeat(64)}`;
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --quiet',
          result: { stdout: '', stderr: '', exitCode: 0 },
        },
        {
          pattern: 'install --name ubuntu ubuntu@sha256:',
          result: { stdout: 'installed', stderr: '', exitCode: 0 },
        },
      ]);
      const manager = new ProotDistroManager(runner);

      expect(manager.installDistro('ubuntu', image).exitCode).toBe(0);
      expect(runner.fileCalls.at(-1)).toEqual({
        command: 'proot-distro',
        args: ['install', '--name', 'ubuntu', image],
      });
    });
  });

  describe('preflightCheck', () => {
    test('should report missing proot-distro', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: { stdout: '', stderr: '', exitCode: 1 },
        },
      ]);
      const check = new ProotDistroManager(runner).preflightCheck('ubuntu');
      expect(check.ready).toBe(false);
      expect(check.missing.length).toBeGreaterThan(0);
    });

    test('should report ready when all components present', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --quiet',
          result: { stdout: 'ubuntu\n', stderr: '', exitCode: 0 },
        },
        {
          pattern: 'list --quiet',
          result: { stdout: 'ubuntu\n', stderr: '', exitCode: 0 },
        },
        {
          pattern: 'command -v freebuff',
          result: {
            stdout: '/root/.bun/bin/freebuff\n',
            stderr: '',
            exitCode: 0,
          },
        },
      ]);
      const check = new ProotDistroManager(runner).preflightCheck('ubuntu');
      expect(check.ready).toBe(true);
      expect(check.missing).toEqual([]);
    });
  });

  describe('runFreeBuff', () => {
    test('should convert Termux CWD to proot CWD in result', () => {
      const runner = createMockRunner([
        {
          pattern: 'proot-distro --help',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --quiet',
          result: { stdout: 'ubuntu\n', stderr: '', exitCode: 0 },
        },
        {
          pattern: 'proot-distro login',
          result: { stdout: 'FreeBuff output', stderr: '', exitCode: 0 },
        },
      ]);
      const termuxHome = '/data/data/com.termux/files/home';
      const result = new ProotDistroManager(runner).runFreeBuff(
        'ubuntu',
        `${termuxHome}/my-project`,
        [],
        { termuxHome, prootHome: '/root' },
      );
      expect(result.termuxCwd).toBe(`${termuxHome}/my-project`);
      expect(result.prootCwd).toBe('/root/my-project');
      expect(result.exitCode).toBe(0);
    });

    test('should pass CWD and FreeBuff arguments as positional argv', () => {
      const runner = createMockRunner([
        {
          pattern: 'list --quiet',
          result: { stdout: 'ubuntu\n', stderr: '', exitCode: 0 },
        },
        {
          pattern: 'proot-distro login',
          result: { stdout: '', stderr: '', exitCode: 0 },
        },
      ]);
      const payload = "quote'$(touch /tmp/pwn);`id`";

      new ProotDistroManager(runner).runFreeBuff(
        'ubuntu',
        '/data/data/com.termux/files/home/project',
        [payload],
        {
          termuxHome: '/data/data/com.termux/files/home',
          prootHome: '/root',
        },
      );

      const call = runner.fileCalls.find(({ args }) => args[0] === 'login');
      expect(call?.command).toBe('proot-distro');
      expect(call?.args).toEqual(
        expect.arrayContaining([
          '/bin/bash',
          '--norc',
          '--noprofile',
          '-c',
          '/root/project',
          payload,
        ]),
      );
      const shellIndex = call?.args.indexOf('-c') ?? -1;
      expect(call?.args[shellIndex + 1]).not.toContain('/root/project');
      expect(call?.args[shellIndex + 1]).not.toContain('touch /tmp/pwn');
      expect(call?.args[shellIndex + 1]).not.toContain('BUN_INSTALL');
      expect(call?.args[shellIndex + 1]).toContain(
        '/opt/freebuff-termux/current-freebuff/bin:/opt/freebuff-termux/current-node/bin:/usr/local/bin:/usr/bin:/bin',
      );
    });
  });

  describe('legacy installer helpers', () => {
    test('fail closed instead of running mutable remote installers', () => {
      const runner = createMockRunner([]);
      const manager = new ProotDistroManager(runner);

      for (const result of [
        manager.installBunInDistro('ubuntu'),
        manager.installFreeBuffInDistro('ubuntu'),
      ]) {
        expect(result.exitCode).toBe(1);
        expect(result.stderr).toContain('scripts/install.sh');
      }
      expect(runner.fileCalls).toHaveLength(0);
    });
  });

  describe('identifier validation', () => {
    test('should reject unsafe distro and user values before command execution', () => {
      const runner = createMockRunner([]);
      const manager = new ProotDistroManager(runner);

      expect(() => manager.installDistro('--help')).toThrow(/distro/i);
      expect(() =>
        manager.execInDistro('ubuntu', 'true', { user: 'root --bind /' }),
      ).toThrow(/user/i);
      expect(runner.fileCalls).toHaveLength(0);
    });
  });
});
