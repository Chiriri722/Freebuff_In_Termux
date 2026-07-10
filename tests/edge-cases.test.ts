import { resolvePath } from '../src/utils/path-utils.js';
import {
  normalizePathForTermux,
  expandTilde,
} from '../src/utils/system-utils.js';
import {
  termuxToProot,
  prootToTermux,
  buildBindMountArgs,
  isTermuxHomePath,
} from '../src/proot/path-bridge.js';

const TERMUX_HOME = '/data/data/com.termux/files/home';
const PROOT_HOME = '/root';
const TERMUX_PREFIX = '/data/data/com.termux/files/usr';
const bridgeConfig = { termuxHome: TERMUX_HOME, prootHome: PROOT_HOME };

const originalPrefix = process.env.PREFIX;
const originalHome = process.env.HOME;

afterEach(() => {
  if (originalPrefix === undefined) delete process.env.PREFIX;
  else process.env.PREFIX = originalPrefix;
  if (originalHome === undefined) delete process.env.HOME;
  else process.env.HOME = originalHome;
});

describe('Edge cases: resolvePath', () => {
  test('should handle empty string', () => {
    process.env.PREFIX = TERMUX_PREFIX;
    expect(resolvePath('')).toBe('');
  });

  test('should handle single slash root path', () => {
    process.env.PREFIX = TERMUX_PREFIX;
    expect(resolvePath('/')).toBe(`${TERMUX_PREFIX}/`);
  });

  test('should handle very long path', () => {
    process.env.PREFIX = TERMUX_PREFIX;
    const deep = '/' + 'a/'.repeat(100) + 'file.txt';
    expect(resolvePath(deep)).toBe(`${TERMUX_PREFIX}${deep}`);
  });

  test('should handle path with spaces', () => {
    process.env.PREFIX = TERMUX_PREFIX;
    expect(resolvePath('/my project/src/my file.ts')).toBe(
      `${TERMUX_PREFIX}/my project/src/my file.ts`,
    );
  });

  test('should handle path with unicode characters', () => {
    process.env.PREFIX = TERMUX_PREFIX;
    expect(resolvePath('/프로젝트/소스/파일.ts')).toBe(
      `${TERMUX_PREFIX}/프로젝트/소스/파일.ts`,
    );
  });

  test('should not double-prefix when path starts with prefix', () => {
    process.env.PREFIX = TERMUX_PREFIX;
    const alreadyPrefixed = `${TERMUX_PREFIX}/etc/config`;
    expect(resolvePath(alreadyPrefixed)).toBe(alreadyPrefixed);
  });

  test('should handle prefix with trailing slash', () => {
    process.env.PREFIX = '/data/data/com.termux/files/usr/';
    expect(resolvePath('/etc/config')).toBe(
      '/data/data/com.termux/files/usr/etc/config',
    );
  });
});

describe('Edge cases: normalizePathForTermux', () => {
  test('should handle only slashes', () => {
    expect(normalizePathForTermux('/////')).toBe('/');
  });

  test('should handle only dots and slashes', () => {
    expect(normalizePathForTermux('/./././.')).toBe('/');
  });

  test('should handle mixed .. and . extensively', () => {
    expect(normalizePathForTermux('/a/./b/../c/./d/../e')).toBe('/a/c/e');
  });

  test('should handle deeply nested .. resolving to root', () => {
    expect(normalizePathForTermux('/a/b/c/../../../..')).toBe('/');
  });

  test('should handle path with spaces', () => {
    // Path segments with spaces are preserved (file names can contain spaces)
    expect(normalizePathForTermux('/my project/ my files')).toBe(
      '/my project/ my files',
    );
  });

  test('should handle unicode path', () => {
    expect(normalizePathForTermux('/프로젝트/소스/../문서')).toBe(
      '/프로젝트/문서',
    );
  });

  test('should handle empty string', () => {
    expect(normalizePathForTermux('')).toBe('');
  });

  test('should handle relative path (no normalization)', () => {
    expect(normalizePathForTermux('../parent/child')).toBe('../parent/child');
  });
});

describe('Edge cases: expandTilde', () => {
  test('should handle empty string', () => {
    expect(expandTilde('')).toBe('');
  });

  test('should handle tilde with empty home', () => {
    expect(expandTilde('~', '')).toBe('');
  });

  test('should handle ~-prefix without slash', () => {
    expect(expandTilde('~backup', '/home')).toBe('~backup');
  });

  test('should handle path starting with ~ but not ~/', () => {
    expect(expandTilde('~user/documents', '/home')).toBe('~user/documents');
  });

  test('should handle home with trailing slash', () => {
    expect(expandTilde('~/dir', '/home/')).toBe('/home//dir');
  });
});

describe('Edge cases: path-bridge', () => {
  test('termuxToProot should handle root path', () => {
    expect(termuxToProot('/', bridgeConfig)).toBe('/');
  });

  test('termuxToProot should handle empty string', () => {
    expect(termuxToProot('', bridgeConfig)).toBe('');
  });

  test('termuxToProot should handle unicode path', () => {
    expect(termuxToProot(`${TERMUX_HOME}/프로젝트/소스`, bridgeConfig)).toBe(
      `${PROOT_HOME}/프로젝트/소스`,
    );
  });

  test('prootToTermux should handle root path', () => {
    expect(prootToTermux('/', bridgeConfig)).toBe('/');
  });

  test('round-trip with deeply nested path', () => {
    const deep = '/' + Array.from({ length: 50 }, (_, i) => `d${i}`).join('/');
    const termuxPath = `${TERMUX_HOME}${deep}`;
    expect(
      prootToTermux(termuxToProot(termuxPath, bridgeConfig), bridgeConfig),
    ).toBe(termuxPath);
  });

  test('round-trip with unicode and spaces', () => {
    const termuxPath = `${TERMUX_HOME}/프로젝트/my project/파일.ts`;
    expect(
      prootToTermux(termuxToProot(termuxPath, bridgeConfig), bridgeConfig),
    ).toBe(termuxPath);
  });

  test('buildBindMountArgs with many mounts', () => {
    const mounts = ['/tmp', '/dev', '/proc', '/sys', '/var'];
    const args = buildBindMountArgs({ bindMounts: mounts });
    expect(args.filter((a) => a === '--bind')).toHaveLength(6);
  });

  test('buildBindMountArgs with duplicate default mount', () => {
    const args = buildBindMountArgs({ bindMounts: ['/storage/emulated/0'] });
    expect(args.filter((a) => a === '/storage/emulated/0')).toHaveLength(2);
  });

  test('isTermuxHomePath with empty string', () => {
    expect(isTermuxHomePath('', bridgeConfig)).toBe(false);
  });

  test('isTermuxHomePath with similar but different prefix', () => {
    expect(
      isTermuxHomePath('/data/data/com.termux/files/usr', bridgeConfig),
    ).toBe(false);
  });
});
