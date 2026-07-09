import { isTermux, getTermuxPrefix } from '../src/utils/termux-utils.js';

describe('Termux environment detection', () => {
  const originalPrefix = process.env.PREFIX;

  afterEach(() => {
    // 테스트 간 환경 변수 격리: 원래 값으로 복원
    if (originalPrefix === undefined) {
      delete process.env.PREFIX;
    } else {
      process.env.PREFIX = originalPrefix;
    }
  });

  test('should detect Termux environment when PREFIX starts with /data/data/com.termux', () => {
    process.env.PREFIX = '/data/data/com.termux/files/usr';
    expect(isTermux()).toBe(true);
  });

  test('should return correct Termux prefix', () => {
    process.env.PREFIX = '/data/data/com.termux/files/usr';
    expect(getTermuxPrefix()).toBe('/data/data/com.termux/files/usr');
  });

  test('should return empty string if not in Termux', () => {
    delete process.env.PREFIX;
    expect(isTermux()).toBe(false);
    expect(getTermuxPrefix()).toBe('');
  });
});
