import { jest } from '@jest/globals';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
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

    test('checks the storage directory without evaluating HOME in a shell', () => {
      process.env.PREFIX = '/data/data/com.termux/files/usr';
      const directoryExists = jest.fn(() => true);
      const home = '/data/data/com.termux/files/home/literal;$(not-a-command)';

      expect(isStorageSetup(home, directoryExists)).toBe(true);
      expect(directoryExists).toHaveBeenCalledWith(`${home}/storage`);
    });

    test('does not treat a regular storage file as a configured directory', () => {
      process.env.PREFIX = '/data/data/com.termux/files/usr';
      const home = mkdtempSync(join(tmpdir(), 'freebuff-storage-'));
      try {
        writeFileSync(join(home, 'storage'), 'not a directory');
        expect(isStorageSetup(home)).toBe(false);
      } finally {
        rmSync(home, { recursive: true, force: true });
      }
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
      expect(['unknown', 'safe', 'caution', 'danger']).toContain(
        assessment.level,
      );
      expect(assessment.recommendedFreeKB).toBeGreaterThan(0);
      expect(assessment.currentFreeKB).toBeGreaterThanOrEqual(0);
      expect(assessment.message).toBeTruthy();
      expect(typeof assessment.message).toBe('string');
    });

    test('should return unknown when memory info unavailable', () => {
      const assess = checkOomRisk as unknown as (
        memoryInfo: null,
      ) => ReturnType<typeof checkOomRisk>;
      const assessment = assess(null);
      expect(assessment.level).toBe('unknown');
      expect(assessment.message).toContain('Unable to read');
    });
  });
});
