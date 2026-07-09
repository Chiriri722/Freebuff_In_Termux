/**
 * Termux 환경 감지 유틸리티
 *
 * Termux(PREFIX=/data/data/com.termux/...) 환경을 감지하고
 * Termux의 파일 시스템 접두사를 반환한다.
 */

/** Termux PREFIX 환경 변수의 기대 접두사 */
const TERMUX_PREFIX_PATTERN = '/data/data/com.termux';

/**
 * 현재 프로세스가 Termux 환경에서 실행 중인지 감지한다.
 * Termux는 PREFIX 환경 변수를 /data/data/com.termux/files/usr 로 설정한다.
 *
 * @returns Termux 환경이면 true, 그렇지 않으면 false
 */
export const isTermux = (): boolean => {
  return (
    !!process.env.PREFIX &&
    process.env.PREFIX.startsWith(TERMUX_PREFIX_PATTERN)
  );
};

/**
 * Termux의 파일 시스템 접두사를 반환한다.
 * 예: /data/data/com.termux/files/usr
 *
 * @returns Termux 환경이면 PREFIX 값, 그렇지 않으면 빈 문자열
 */
export const getTermuxPrefix = (): string => {
  if (isTermux()) {
    return process.env.PREFIX || '';
  }
  return '';
};
