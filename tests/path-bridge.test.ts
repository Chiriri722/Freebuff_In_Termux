import {
  termuxToProot,
  prootToTermux,
  buildBindMountArgs,
  BindMountError,
  isTermuxHomePath,
  getProotRootPath,
} from '../src/proot/path-bridge.js';

const TERMUX_HOME = '/data/data/com.termux/files/home';
const PROOT_HOME = '/root';
const PREFIX = '/data/data/com.termux/files/usr';

describe('Path Bridge: Termux ↔ proot conversion', () => {
  describe('termuxToProot', () => {
    test('should map Termux home to proot home', () => {
      expect(
        termuxToProot(TERMUX_HOME, {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
        }),
      ).toBe(PROOT_HOME);
    });

    test('should map Termux home subdirectory to proot home subdirectory', () => {
      expect(
        termuxToProot(`${TERMUX_HOME}/project`, {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
        }),
      ).toBe(`${PROOT_HOME}/project`);
    });

    test('should preserve shared storage paths when storage bind is enabled', () => {
      expect(
        termuxToProot('/storage/emulated/0/Documents', {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
          storageBind: true,
        }),
      ).toBe('/storage/emulated/0/Documents');
    });

    test('should reject shared storage paths when storage bind is disabled', () => {
      expect(() =>
        termuxToProot('/storage/emulated/0/Documents', {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
        }),
      ).toThrow(/storage bind/i);
    });

    test('should not transform unrelated absolute paths', () => {
      expect(
        termuxToProot('/usr/bin/tool', {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
        }),
      ).toBe('/usr/bin/tool');
    });

    test('should normalize paths before conversion', () => {
      expect(
        termuxToProot(`${TERMUX_HOME}/./project/../app`, {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
        }),
      ).toBe(`${PROOT_HOME}/app`);
    });
  });

  describe('prootToTermux', () => {
    test('should map proot home to Termux home', () => {
      expect(
        prootToTermux(PROOT_HOME, {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
        }),
      ).toBe(TERMUX_HOME);
    });

    test('should map proot home subdirectory to Termux home subdirectory', () => {
      expect(
        prootToTermux(`${PROOT_HOME}/project`, {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
        }),
      ).toBe(`${TERMUX_HOME}/project`);
    });

    test('should preserve shared storage paths', () => {
      expect(
        prootToTermux('/storage/emulated/0/Downloads', {
          termuxHome: TERMUX_HOME,
          prootHome: PROOT_HOME,
        }),
      ).toBe('/storage/emulated/0/Downloads');
    });

    test('should be inverse of termuxToProot', () => {
      const original = `${TERMUX_HOME}/my-project/src`;
      const config = { termuxHome: TERMUX_HOME, prootHome: PROOT_HOME };
      const prootPath = termuxToProot(original, config);
      const backToTermux = prootToTermux(prootPath, config);
      expect(backToTermux).toBe(original);
    });
  });

  describe('buildBindMountArgs', () => {
    test('should not bind shared storage unless explicitly enabled', () => {
      const args = buildBindMountArgs();
      expect(args).not.toContain('/storage/emulated/0');
    });

    test('should include shared storage once when explicitly enabled', () => {
      const args = buildBindMountArgs(
        {
          storageBind: true,
          bindMounts: ['/storage/emulated/0'],
        },
        () => true,
      );
      expect(args.filter((arg) => arg === '/storage/emulated/0')).toHaveLength(
        1,
      );
    });

    test('should include custom bind mounts', () => {
      const args = buildBindMountArgs(
        { bindMounts: ['/tmp', '/dev'] },
        () => true,
      );
      expect(args).toContain('/tmp');
      expect(args).toContain('/dev');
    });

    test('rejects a missing custom mount with a structured error', () => {
      try {
        buildBindMountArgs({ bindMounts: ['/missing/project'] }, () => false);
        throw new Error('Expected buildBindMountArgs to reject the mount');
      } catch (error) {
        expect(error).toBeInstanceOf(BindMountError);
        expect(error).toMatchObject({
          code: 'BIND_MOUNT_NOT_FOUND',
          mount: '/missing/project',
        });
      }
    });
  });

  describe('isTermuxHomePath', () => {
    test('should return true for Termux home itself', () => {
      expect(isTermuxHomePath(TERMUX_HOME, { termuxHome: TERMUX_HOME })).toBe(
        true,
      );
    });

    test('should return true for Termux home subdirectory', () => {
      expect(
        isTermuxHomePath(`${TERMUX_HOME}/project`, { termuxHome: TERMUX_HOME }),
      ).toBe(true);
    });

    test('should return false for non-Termux-home paths', () => {
      expect(isTermuxHomePath('/usr/bin', { termuxHome: TERMUX_HOME })).toBe(
        false,
      );
    });
  });

  describe('getProotRootPath', () => {
    test('should return correct path with explicit prefix', () => {
      expect(getProotRootPath('ubuntu', PREFIX)).toBe(
        `${PREFIX}/var/lib/proot-distro/containers/ubuntu/rootfs`,
      );
    });

    test('should default to the Termux PREFIX path, not HOME', () => {
      const originalPrefix = process.env.PREFIX;
      delete process.env.PREFIX;
      try {
        expect(getProotRootPath('ubuntu')).toBe(
          '/data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu/rootfs',
        );
      } finally {
        if (originalPrefix === undefined) delete process.env.PREFIX;
        else process.env.PREFIX = originalPrefix;
      }
    });

    test('should reject unsafe distro names', () => {
      expect(() => getProotRootPath('../escape', PREFIX)).toThrow(/distro/i);
    });
  });
});
