import { ProotDistroManager } from '../src/proot/proot-wrapper.js';
import type { CommandRunner, ExecResult } from '../src/types.js';

/** 테스트용 mock CommandRunner를 생성한다. */
const createMockRunner = (
  responses: { pattern: string | RegExp; result: ExecResult }[],
): CommandRunner => {
  return {
    exec(command: string): ExecResult {
      for (const { pattern, result } of responses) {
        if (typeof pattern === 'string') {
          if (command.includes(pattern)) return result;
        } else {
          if (pattern.test(command)) return result;
        }
      }
      return { stdout: '', stderr: 'No mock match', exitCode: 127 };
    },
  };
};

describe('ProotDistroManager', () => {
  describe('isProotDistroInstalled', () => {
    test('should return true when proot-distro command exists', () => {
      const runner = createMockRunner([
        {
          pattern: 'command -v proot-distro',
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
    });

    test('should return false when proot-distro not found', () => {
      const runner = createMockRunner([
        {
          pattern: 'command -v proot-distro',
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
          pattern: 'command -v proot-distro',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --installed',
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
          pattern: 'command -v proot-distro',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --installed',
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
          pattern: 'list --installed',
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
          pattern: 'list --installed',
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
          pattern: 'command -v proot-distro',
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
          pattern: 'command -v proot-distro',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: 'list --installed',
          result: { stdout: 'ubuntu\n', stderr: '', exitCode: 0 },
        },
      ]);
      const result = new ProotDistroManager(runner).installDistro('ubuntu');
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain('already installed');
    });
  });

  describe('preflightCheck', () => {
    test('should report missing proot-distro', () => {
      const runner = createMockRunner([
        {
          pattern: 'command -v proot-distro',
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
          pattern: 'command -v proot-distro',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: /list --installed.*grep/,
          result: { stdout: 'ubuntu\n', stderr: '', exitCode: 0 },
        },
        {
          pattern: 'list --installed',
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
          pattern: 'command -v proot-distro',
          result: {
            stdout: '/usr/bin/proot-distro\n',
            stderr: '',
            exitCode: 0,
          },
        },
        {
          pattern: /list --installed.*grep/,
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
  });
});
