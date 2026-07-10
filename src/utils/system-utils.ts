/**
 * 시스템 환경 유틸리티
 *
 * Termux/Android 환경의 시스템 정보(아키텍처, Android 버전, 저장소 경로 등)를
 * 조회하고, 명령어 존재 여부를 확인하며, 경로를 정규화하는 유틸리티 함수들을 제공한다.
 */

import { execSync } from 'node:child_process';
import { isTermux } from './termux-utils.js';
import type { Architecture } from '../types.js';

/** Android 공유 저장소 기본 경로 */
const ANDROID_STORAGE_PATH = '/storage/emulated/0';

/**
 * process.arch 값을 Termux/Android 아키텍처 이름으로 매핑한다.
 *
 * Node.js process.arch: 'arm64', 'ia32', 'x64', 'arm', 'mips', 'mipsel'
 * Android/Termux:       'aarch64', 'i386',   'x86_64', 'arm'
 */
const ARCH_MAP: Record<string, Architecture> = {
  arm64: 'aarch64',
  ia32: 'i386',
  x64: 'x86_64',
  arm: 'arm',
};

/**
 * 현재 CPU 아키텍처를 반환한다.
 *
 * @returns 아키텍처 문자열 ('aarch64', 'arm', 'x86_64', 'i386', 'unknown')
 */
export const getArch = (): Architecture => {
  return ARCH_MAP[process.arch] ?? 'unknown';
};

/**
 * Android 버전을 반환한다.
 * Termux 환경에서는 `getprop ro.build.version.release`를 실행하여 조회한다.
 * 명령 실행 실패 시 null을 반환한다.
 *
 * @returns Android 버전 문자열 (예: "14") 또는 null
 */
export const getAndroidVersion = (): string | null => {
  if (!isTermux()) {
    return null;
  }
  try {
    const version = execSync('getprop ro.build.version.release', {
      encoding: 'utf-8',
      timeout: 5000,
    }).trim();
    return version || null;
  } catch {
    return null;
  }
};

/**
 * Android 공유 저장소 경로를 반환한다.
 * Termux에서 `termux-setup-storage`를 실행한 후 접근 가능한 경로이다.
 *
 * @returns 저장소 경로 (기본값: '/storage/emulated/0')
 */
export const getStoragePath = (): string => {
  return ANDROID_STORAGE_PATH;
};

/**
 * 지정된 명령어가 시스템 PATH에 존재하는지 확인한다.
 * Windows에서는 `where`, Linux/macOS/Termux에서는 `command -v`를 사용한다.
 *
 * @param command - 확인할 명령어 이름
 * @returns 명령어가 존재하면 true, 그렇지 않으면 false
 */
export const isCommandAvailable = (command: string): boolean => {
  const checkCmd =
    process.platform === 'win32' ? `where ${command}` : `command -v ${command}`;
  try {
    execSync(checkCmd, {
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
 * proot-distro 명령어가 설치되어 있는지 확인한다.
 *
 * @returns proot-distro가 사용 가능하면 true
 */
export const isProotAvailable = (): boolean => {
  return isCommandAvailable('proot-distro');
};

/**
 * 경로의 틸다(~)를 실제 홈 디렉토리로 확장한다.
 *
 * @param path - 확장할 경로
 * @param home - 홈 디렉토리 (기본값: process.env.HOME)
 * @returns 틸다가 확장된 경로
 */
export const expandTilde = (path: string, home?: string): string => {
  const homeDir = home ?? process.env.HOME ?? '';
  if (path === '~') {
    return homeDir;
  }
  if (path.startsWith('~/')) {
    return `${homeDir}${path.slice(1)}`;
  }
  return path;
};

/**
 * 경로를 정규화한다.
 * - 틸다(~) 확장
 * - 후행 슬래시 제거 (루트 '/' 제외)
 * - 중복 슬래시 축약
 * - '.' 및 '..' 세그먼트 해석
 *
 * @param path - 정규화할 경로
 * @returns 정규화된 절대 경로
 */
export const normalizePathForTermux = (path: string): string => {
  // 틸다 확장
  const normalized = expandTilde(path);

  // 절대 경로가 아니면 그대로 반환 (상대 경로는 정규화하지 않음)
  if (!normalized.startsWith('/')) {
    return normalized;
  }

  // 세그먼트 분해 및 정규화
  const segments = normalized.split('/');
  const resolved: string[] = [];

  for (const segment of segments) {
    // 빈 세그먼트 (중복 슬래시) 또는 현재 디렉토리 (.) 무시
    if (segment === '' || segment === '.') {
      continue;
    }
    // 상위 디렉토리 (..) 처리
    if (segment === '..') {
      resolved.pop();
      continue;
    }
    resolved.push(segment);
  }

  // 루트 경로 처리: resolved가 비어 있으면 '/'
  const result = '/' + resolved.join('/');
  return result === '' ? '/' : result;
};
