/**
 * 경로 변환 유틸리티
 *
 * Termux 환경에서 시스템 절대 경로를 Termux PREFIX 기반 경로로 변환한다.
 * 예: /etc/config → /data/data/com.termux/files/usr/etc/config
 */

import { isTermux, getTermuxPrefix } from './termux-utils.js';

/**
 * 주어진 경로를 Termux 환경에 맞게 보정한다.
 *
 * 동작 규칙:
 * - Termux 환경이 아니면 입력 경로를 그대로 반환
 * - 상대 경로(./, ../, 또는 /로 시작하지 않음)면 그대로 반환
 * - 이미 Termux PREFIX로 시작하면 중복 적용 방지를 위해 그대로 반환
 * - 절대 경로이고 PREFIX로 시작하지 않으면 PREFIX를 앞에 추가
 *
 * @param path - 변환할 파일 경로
 * @returns Termux 환경에 맞게 보정된 경로
 */
export const resolvePath = (path: string): string => {
  // 입력 검증: 빈 문자열은 그대로 반환
  if (!path || path.length === 0) {
    return path;
  }

  // Termux 환경이 아니면 변환 없음
  if (!isTermux()) {
    return path;
  }

  // 상대 경로는 변환하지 않음 (/로 시작하지 않는 경로)
  if (!path.startsWith('/')) {
    return path;
  }

  const prefix = getTermuxPrefix().replace(/\/+$/, '');

  // 이미 PREFIX로 시작하면 중복 적용 방지
  if (path === prefix || path.startsWith(`${prefix}/`)) {
    return path;
  }

  // Android의 실제 절대 경로(/storage, /data 등)는 보존한다.
  // 전통적인 /usr 경로와 Termux PREFIX 직속 시스템 디렉터리만 변환한다.
  if (path === '/usr') {
    return prefix;
  }
  if (path.startsWith('/usr/')) {
    return `${prefix}${path.slice('/usr'.length)}`;
  }

  const rootSegment = path.slice(1).split('/', 1)[0];
  const prefixRoots = new Set([
    'bin',
    'etc',
    'include',
    'lib',
    'libexec',
    'share',
    'tmp',
    'var',
  ]);
  return prefixRoots.has(rootSegment) ? `${prefix}${path}` : path;
};
