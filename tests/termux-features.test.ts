import {
  acquireWakeLock,
  releaseWakeLock,
  isWakeLockAvailable,
  setupStorage,
  isStorageSetup,
  getMemoryInfo,
  checkOomRisk,
} from '../src/utils/termux-features.js';

describe('Termux-specific features', () => {
  const originalPrefix = process.env.PREFIX;

  afterEach(() => {
    if (originalPrefix === undefined) {
      delete process.env.PREFIX;
    } else {
      process.env.PREFIX = originalPrefix;
    }
  });

  describe('acquireWakeLock / releaseWakeLock', () => {
    test('should return false when not in Termux', () => {
      delete process.env.PREFIX;
      expect(acquireWakeLock()).toBe(false);
      expect(releaseWakeLock()).toBe(false);
    });
  });

  describe('isWakeLockAvailable', () => {
    test('should return false when not in Termux', () => {
      delete process.env.PREFIX;
      expect(isWakeLockAvailable()).toBe(false);
    });
  });

  describe('setupStorage / isStorageSetup', () => {
    test('should return false when not in Termux', () => {
      delete process.env.PREFIX;
      expect(setupStorage()).toBe(false);
      expect(isStorageSetup()).toBe(false);
    });
  });

  describe('getMemoryInfo', () => {
    test('should return memory info or null', () => {
      const info = getMemoryInfo();
      // /proc/meminfo는 Linux/WSL/Termux에서 사용 가능, Windows에서는 null
      if (info) {
        expect(info.total).toBeGreaterThan(0);
        expect(info.available).toBeGreaterThanOrEqual(0);
        expect(info.used).toBeGreaterThanOrEqual(0);
        expect(info.usagePercent).toBeGreaterThanOrEqual(0);
        expect(info.usagePercent).toBeLessThanOrEqual(100);
        expect(info.total).toBe(info.used + info.available);
      }
    });
  });

  describe('checkOomRisk', () => {
    test('should return an assessment object', () => {
      const assessment = checkOomRisk();
      expect(assessment).toBeDefined();
      expect(['safe', 'caution', 'danger']).toContain(assessment.level);
      expect(assessment.recommendedFreeKB).toBeGreaterThan(0);
      expect(assessment.currentFreeKB).toBeGreaterThanOrEqual(0);
      expect(assessment.message).toBeTruthy();
      expect(typeof assessment.message).toBe('string');
    });

    test('should return safe when memory info unavailable', () => {
      // Windows에서 /proc/meminfo가 없는 경우
      const assessment = checkOomRisk();
      if (assessment.currentFreeKB === 0) {
        expect(assessment.level).toBe('safe');
        expect(assessment.message).toContain('Unable to read');
      }
    });
  });
});
