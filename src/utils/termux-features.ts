/**
 * Termux 특화 기능 (Phase 3D)
 *
 * Android/Termux 환경의 고유 제약에 대응하는 유틸리티:
 * - Wake Lock: 장시간 실행 시 화면 꺼짐/Doze 모드 방지
 * - 저장소 권한: Android 공유 저장소 접근 설정
 * - 메모리 관리: OOM Killer 위험도 평가
 */

import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { isTermux } from './termux-utils.js';
import { isCommandAvailable } from './system-utils.js';
import type { MemoryInfo, OomRiskAssessment } from '../types.js';

// ─── Wake Lock ──────────────────────────────────────────────

/**
 * Termux Wake Lock을 획득한다.
 * 장시간 FreeBuff 실행 시 Android의 Doze 모드나
 * 화면 꺼짐으로 인한 프로세스 일시 정지를 방지한다.
 *
 * @returns 성공 여부
 */
export const acquireWakeLock = (): boolean => {
  if (!isTermux()) return false;
  try {
    execSync('termux-wake-lock', {
      encoding: 'utf-8',
      timeout: 5000,
      stdio: 'pipe',
    });
    return true;
  } catch {
    return false;
  }
};

/**
 * Termux Wake Lock을 해제한다.
 * FreeBuff 실행 완료 후 배터리 절약을 위해 호출한다.
 *
 * @returns 성공 여부
 */
export const releaseWakeLock = (): boolean => {
  if (!isTermux()) return false;
  try {
    execSync('termux-wake-unlock', {
      encoding: 'utf-8',
      timeout: 5000,
      stdio: 'pipe',
    });
    return true;
  } catch {
    return false;
  }
};

/**
 * termux-wake-lock 명령어가 사용 가능한지 확인한다.
 */
export const isWakeLockAvailable = (): boolean => {
  return isTermux() && isCommandAvailable('termux-wake-lock');
};

// ─── 저장소 권한 ────────────────────────────────────────────

/**
 * Android 공유 저장소 접근 권한을 설정한다.
 * `termux-setup-storage`를 실행하여 ~/storage 심볼릭 링크를 생성한다.
 *
 * @returns 성공 여부
 */
export const setupStorage = (): boolean => {
  if (!isTermux()) return false;
  try {
    execSync('termux-setup-storage', {
      encoding: 'utf-8',
      timeout: 10000,
      stdio: 'pipe',
    });
    return true;
  } catch {
    return false;
  }
};

/**
 * 저장소가 이미 설정되어 있는지 확인한다.
 * ~/storage 디렉토리 존재 여부로 판단한다.
 */
export const isStorageSetup = (): boolean => {
  if (!isTermux() || !process.env.HOME) return false;
  try {
    execSync(`test -d "${process.env.HOME}/storage"`, {
      encoding: 'utf-8',
      timeout: 5000,
      stdio: 'pipe',
    });
    return true;
  } catch {
    return false;
  }
};

// ─── 메모리 관리 ────────────────────────────────────────────

/** FreeBuff 실행 권장 최소 여유 메모리 (KB) — 약 512MB */
const RECOMMENDED_FREE_KB = 512 * 1024;

/** 위험 임계값 (KB) — 약 128MB */
const DANGER_THRESHOLD_KB = 128 * 1024;

/**
 * /proc/meminfo를 파싱하여 메모리 정보를 반환한다.
 * Android/Termux에서도 /proc/meminfo에 접근할 수 있다.
 *
 * @returns 메모리 정보 객체, 실패 시 null
 */
export const getMemoryInfo = (): MemoryInfo | null => {
  try {
    const meminfo = readFileSync('/proc/meminfo', 'utf-8');
    const parse = (key: string): number => {
      const match = meminfo.match(new RegExp(`^${key}:\\s+(\\d+)`, 'm'));
      return match ? parseInt(match[1], 10) : 0;
    };

    const total = parse('MemTotal');
    const available = parse('MemAvailable');

    if (total === 0) return null;

    const used = total - available;
    const usagePercent = Math.round((used / total) * 100);

    return { total, available, used, usagePercent };
  } catch {
    return null;
  }
};

/**
 * OOM Killer 위험도를 평가한다.
 * FreeBuff(proot + Bun)는 메모리를 많이 사용하므로
 * 실행 전 여유 메모리를 확인하여 OOM 종료를 방지한다.
 *
 * @returns 위험도 평가 결과
 */
export const checkOomRisk = (): OomRiskAssessment => {
  const memInfo = getMemoryInfo();

  if (!memInfo) {
    return {
      level: 'safe',
      recommendedFreeKB: RECOMMENDED_FREE_KB,
      currentFreeKB: 0,
      message: 'Unable to read memory info. Proceed with caution.',
    };
  }

  const currentFreeKB = memInfo.available;

  if (currentFreeKB < DANGER_THRESHOLD_KB) {
    return {
      level: 'danger',
      recommendedFreeKB: RECOMMENDED_FREE_KB,
      currentFreeKB,
      message:
        `Critical: Only ${Math.round(currentFreeKB / 1024)}MB free. ` +
        `FreeBuff will likely be killed by OOM Killer. Close other apps first.`,
    };
  }

  if (currentFreeKB < RECOMMENDED_FREE_KB) {
    return {
      level: 'caution',
      recommendedFreeKB: RECOMMENDED_FREE_KB,
      currentFreeKB,
      message:
        `Caution: ${Math.round(currentFreeKB / 1024)}MB free. ` +
        `Recommended ${Math.round(RECOMMENDED_FREE_KB / 1024)}MB. May experience OOM kills.`,
    };
  }

  return {
    level: 'safe',
    recommendedFreeKB: RECOMMENDED_FREE_KB,
    currentFreeKB,
    message: `Safe: ${Math.round(currentFreeKB / 1024)}MB free. Sufficient for FreeBuff.`,
  };
};
