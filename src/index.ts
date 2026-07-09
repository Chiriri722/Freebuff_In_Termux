/**
 * FreeBuff Termux 변환 레이어 — 진입점 모듈
 *
 * Termux 환경 감지 및 경로 보정 유틸리티를 통합 export 한다.
 * 이 모듈은 향후 proot-distro 래퍼 및 FreeBuff 런처와 함께
 * B+C 하이브리드 전략의 기반 레이어로 확장될 예정이다.
 */

import { isTermux, getTermuxPrefix } from './utils/termux-utils.js';
import { resolvePath } from './utils/path-utils.js';
import { fileURLToPath } from 'node:url';

// 핵심 유틸리티 재수출
export { isTermux, getTermuxPrefix, resolvePath };

/**
 * FreeBuff Termux 변환 레이어의 기본 진입 함수.
 * 현재 환경이 Termux인지 감지하고 정보를 출력한다.
 */
export const run = (): void => {
  console.log('Freebuff Termux Conversion Layer');
  if (isTermux()) {
    console.log(`Running in Termux environment. Prefix: ${getTermuxPrefix()}`);
  } else {
    console.log('Running in standard environment.');
  }
};

// 직접 실행 시 run() 호출 (node dist/index.js)
// Windows/Linux/macOS 경로 차이를 처리하기 위해 fileURLToPath 사용
const isMainModule = process.argv[1] &&
  fileURLToPath(import.meta.url) === process.argv[1];
if (isMainModule) {
  run();
}
