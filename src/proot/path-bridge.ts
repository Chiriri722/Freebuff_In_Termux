/**
 * 경로 브리지 — Termux ↔ proot-distro 양방향 경로 변환
 *
 * Termux 환경에서 proot-distro로 Linux distro를 실행할 때,
 * Termux의 파일 시스템 경로와 proot 내부 경로 간의 변환을 담당한다.
 *
 * 핵심 매핑 규칙:
 * - Termux 홈 (/data/data/com.termux/files/home) ↔ proot 홈 (/root)
 * - Termux 공유 저장소 (/storage/emulated/0) ↔ proot 마운트 포인트 (/storage/emulated/0)
 * - proot 절대 경로 중 Termux 홈이 아닌 경로는 그대로 유지
 */

import { normalizePathForTermux } from '../utils/system-utils.js';
import type { ProotDistroConfig } from '../types.js';

/** Termux 홈 디렉토리 기본값 */
const DEFAULT_TERMUX_HOME = '/data/data/com.termux/files/home';

/** proot 내 홈 디렉토리 기본값 (root 사용자) */
const DEFAULT_PROOT_HOME = '/root';

/**
 * 설정에서 누락된 기본값을 채운 완전한 설정을 반환한다.
 */
const resolveConfig = (config: Partial<ProotDistroConfig>): Required<Pick<ProotDistroConfig, 'distro' | 'user' | 'termuxHome' | 'prootHome'>> & { bindMounts: string[] } => {
  return {
    distro: config.distro ?? 'ubuntu',
    user: config.user ?? 'root',
    termuxHome: config.termuxHome ?? process.env.HOME ?? DEFAULT_TERMUX_HOME,
    prootHome: config.prootHome ?? DEFAULT_PROOT_HOME,
    bindMounts: config.bindMounts ?? [],
  };
};

/**
 * proot-distro의 설치 경로(루트 파일 시스템)를 반환한다.
 * proot-distro는 $PREFIX/var/lib/proot-distro/installed-rootfs/<distro>에 설치된다.
 *
 * @param distro - distro 이름
 * @param prefix - Termux PREFIX (기본값: process.env.PREFIX)
 * @returns distro 루트 파일 시스템 경로
 */
export const getProotRootPath = (distro: string, prefix?: string): string => {
  const termuxPrefix = prefix ?? process.env.PREFIX ?? DEFAULT_TERMUX_HOME;
  return `${termuxPrefix}/var/lib/proot-distro/installed-rootfs/${distro}`;
};

/**
 * Termux 경로를 proot 내부 경로로 변환한다.
 *
 * 변환 규칙:
 * 1. Termux 홈 디렉토리 하위 경로 → proot 홈 디렉토리 하위 경로
 *    예: /data/data/com.termux/files/home/project → /root/project
 * 2. 공유 저장소 경로는 그대로 유지 (bind mount됨)
 *    예: /storage/emulated/0/Documents → /storage/emulated/0/Documents
 * 3. 그 외 경로는 변환하지 않음
 *
 * @param termuxPath - Termux 측 경로
 * @param config - proot 설정
 * @returns proot 내부 경로
 */
export const termuxToProot = (
  termuxPath: string,
  config: Partial<ProotDistroConfig> = {}
): string => {
  const { termuxHome, prootHome } = resolveConfig(config);
  const normalized = normalizePathForTermux(termuxPath);

  // Termux 홈 하위 경로를 proot 홈으로 매핑
  if (normalized === termuxHome) {
    return prootHome;
  }
  if (normalized.startsWith(termuxHome + '/')) {
    return prootHome + normalized.slice(termuxHome.length);
  }

  // 공유 저장소 경로는 그대로 유지 (bind mount)
  if (normalized.startsWith('/storage/')) {
    return normalized;
  }

  // 그 외 경로는 변환하지 않음
  return normalized;
};

/**
 * proot 내부 경로를 Termux 경로로 변환한다.
 *
 * 변환 규칙 (termuxToProot의 역방향):
 * 1. proot 홈 디렉토리 하위 경로 → Termux 홈 디렉토리 하위 경로
 *    예: /root/project → /data/data/com.termux/files/home/project
 * 2. 공유 저장소 경로는 그대로 유지
 * 3. 그 외 경로는 변환하지 않음
 *
 * @param prootPath - proot 내부 경로
 * @param config - proot 설정
 * @returns Termux 측 경로
 */
export const prootToTermux = (
  prootPath: string,
  config: Partial<ProotDistroConfig> = {}
): string => {
  const { termuxHome, prootHome } = resolveConfig(config);
  const normalized = normalizePathForTermux(prootPath);

  // proot 홈 하위 경로를 Termux 홈으로 매핑
  if (normalized === prootHome) {
    return termuxHome;
  }
  if (normalized.startsWith(prootHome + '/')) {
    return termuxHome + normalized.slice(prootHome.length);
  }

  // 공유 저장소 경로는 그대로 유지
  if (normalized.startsWith('/storage/')) {
    return normalized;
  }

  // 그 외 경로는 변환하지 않음
  return normalized;
};

/**
 * proot-distro login 명령어에 전달할 bind mount 인자를 생성한다.
 *
 * @param config - proot 설정
 * @returns bind mount 인자 배열 (예: ['--bind', '/storage/emulated/0'])
 */
export const buildBindMountArgs = (
  config: Partial<ProotDistroConfig> = {}
): string[] => {
  const { bindMounts } = resolveConfig(config);
  const args: string[] = [];

  // 공유 저장소는 항상 bind mount
  args.push('--bind', '/storage/emulated/0');

  // 사용자 지정 bind mount 추가
  for (const mount of bindMounts) {
    args.push('--bind', mount);
  }

  return args;
};

/**
 * 주어진 Termux 경로가 proot 홈으로 매핑 가능한지 확인한다.
 *
 * @param termuxPath - 확인할 Termux 경로
 * @param config - proot 설정
 * @returns 매핑 가능하면 true
 */
export const isTermuxHomePath = (
  termuxPath: string,
  config: Partial<ProotDistroConfig> = {}
): boolean => {
  const { termuxHome } = resolveConfig(config);
  const normalized = normalizePathForTermux(termuxPath);
  return normalized === termuxHome || normalized.startsWith(termuxHome + '/');
};
