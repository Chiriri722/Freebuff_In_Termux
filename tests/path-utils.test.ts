import { resolvePath } from '../src/utils/path-utils.js';

describe('Path resolution for Termux', () => {
  const termuxPrefix = '/data/data/com.termux/files/usr';
  const originalPrefix = process.env.PREFIX;

  afterEach(() => {
    // 테스트 간 환경 변수 격리: 원래 값으로 복원
    if (originalPrefix === undefined) {
      delete process.env.PREFIX;
    } else {
      process.env.PREFIX = originalPrefix;
    }
  });

  test('should resolve relative path correctly in standard environment', () => {
    delete process.env.PREFIX;
    expect(resolvePath('test.txt')).toBe('test.txt');
  });

  test('should prepend Termux prefix for absolute paths in Termux environment', () => {
    process.env.PREFIX = termuxPrefix;
    expect(resolvePath('/etc/config')).toBe(`${termuxPrefix}/etc/config`);
  });

  test('should not prepend Termux prefix if already present', () => {
    process.env.PREFIX = termuxPrefix;
    const path = `${termuxPrefix}/etc/config`;
    expect(resolvePath(path)).toBe(path);
  });

  test('should return empty string as-is for empty input', () => {
    process.env.PREFIX = termuxPrefix;
    expect(resolvePath('')).toBe('');
  });

  test('should not transform relative paths in Termux environment', () => {
    process.env.PREFIX = termuxPrefix;
    expect(resolvePath('./relative/path')).toBe('./relative/path');
    expect(resolvePath('../parent')).toBe('../parent');
    expect(resolvePath('relative-no-slash')).toBe('relative-no-slash');
  });

  test('should not transform absolute paths in standard environment', () => {
    delete process.env.PREFIX;
    expect(resolvePath('/etc/config')).toBe('/etc/config');
  });
});
