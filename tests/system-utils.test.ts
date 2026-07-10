import {
  getArch,
  getStoragePath,
  isCommandAvailable,
  expandTilde,
  normalizePathForTermux,
} from '../src/utils/system-utils.js';

describe('System utilities', () => {
  describe('getArch', () => {
    test('should return a valid architecture string', () => {
      const arch = getArch();
      expect(['aarch64', 'arm', 'x86_64', 'i386', 'unknown']).toContain(arch);
    });
  });

  describe('getStoragePath', () => {
    test('should return Android shared storage path', () => {
      expect(getStoragePath()).toBe('/storage/emulated/0');
    });
  });

  describe('isCommandAvailable', () => {
    test('should find existing command (node)', () => {
      expect(isCommandAvailable('node')).toBe(true);
    });

    test('should return false for non-existent command', () => {
      expect(isCommandAvailable('this-command-does-not-exist-12345')).toBe(false);
    });
  });

  describe('expandTilde', () => {
    test('should expand bare tilde to home', () => {
      expect(expandTilde('~', '/home/user')).toBe('/home/user');
    });

    test('should expand tilde-slash path', () => {
      expect(expandTilde('~/documents', '/home/user')).toBe('/home/user/documents');
    });

    test('should not modify non-tilde paths', () => {
      expect(expandTilde('/etc/config', '/home/user')).toBe('/etc/config');
    });

    test('should use process.env.HOME when no home provided', () => {
      const result = expandTilde('~/test');
      expect(result).toContain('test');
    });
  });

  describe('normalizePathForTermux', () => {
    test('should resolve . segments', () => {
      expect(normalizePathForTermux('/a/./b/./c')).toBe('/a/b/c');
    });

    test('should resolve .. segments', () => {
      expect(normalizePathForTermux('/a/b/../c')).toBe('/a/c');
    });

    test('should collapse duplicate slashes', () => {
      expect(normalizePathForTermux('/a//b///c')).toBe('/a/b/c');
    });

    test('should handle root path', () => {
      expect(normalizePathForTermux('/')).toBe('/');
    });

    test('should not modify relative paths', () => {
      expect(normalizePathForTermux('relative/path')).toBe('relative/path');
    });

    test('should handle trailing slash', () => {
      expect(normalizePathForTermux('/a/b/')).toBe('/a/b');
    });

    test('should not go above root with .. ', () => {
      expect(normalizePathForTermux('/../../../etc')).toBe('/etc');
    });

    test('should expand tilde', () => {
      const result = normalizePathForTermux('~/project');
      expect(result).toContain('project');
      expect(result.startsWith('/')).toBe(true);
    });
  });
});
