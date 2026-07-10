/**
 * FreeBuff Termux 변환 레이어 — 진입점 모듈
 *
 * Termux 환경 감지, 경로 보정, 시스템 유틸리티,
 * proot-distro 래퍼, 경로 브리지를 통합 export 한다.
 * B+C 하이브리드 전략의 공용 API 진입점이다.
 */

import { fileURLToPath } from 'node:url';

// 기존 유틸리티
import { isTermux, getTermuxPrefix } from './utils/termux-utils.js';
import { resolvePath } from './utils/path-utils.js';

// 새 유틸리티 (Phase 2A)
import {
  getArch,
  getAndroidVersion,
  getStoragePath,
  isCommandAvailable,
  isProotAvailable,
  expandTilde,
  normalizePathForTermux,
} from './utils/system-utils.js';

// 경로 브리지 (Phase 2C)
import {
  termuxToProot,
  prootToTermux,
  buildBindMountArgs,
  isTermuxHomePath,
  getProotRootPath,
} from './proot/path-bridge.js';

// proot 래퍼 (Phase 2B)
import { ProotDistroManager } from './proot/proot-wrapper.js';

// 타입 재수출
export type {
  CommandRunner,
  ExecResult,
  ExecOptions,
  Architecture,
  ProotDistroConfig,
  FreeBuffRunResult,
} from './types.js';

// 유틸리티 재수출
export {
  isTermux,
  getTermuxPrefix,
  resolvePath,
  getArch,
  getAndroidVersion,
  getStoragePath,
  isCommandAvailable,
  isProotAvailable,
  expandTilde,
  normalizePathForTermux,
};

// 경로 브리지 재수출
export {
  termuxToProot,
  prootToTermux,
  buildBindMountArgs,
  isTermuxHomePath,
  getProotRootPath,
};

// proot 래퍼 재수출
export { ProotDistroManager };

/**
 * FreeBuff Termux 변환 레이어의 기본 진입 함수.
 * 현재 환경 정보를 감지하고 출력한다.
 */
export const run = (): void => {
  console.log('Freebuff Termux Conversion Layer');
  if (isTermux()) {
    console.log(`Running in Termux environment. Prefix: ${getTermuxPrefix()}`);
    console.log(`Architecture: ${getArch()}`);
    const androidVer = getAndroidVersion();
    if (androidVer) {
      console.log(`Android version: ${androidVer}`);
    }
    console.log(`proot-distro available: ${isProotAvailable()}`);
  } else {
    console.log('Running in standard environment.');
    console.log(`Architecture: ${getArch()}`);
  }
};

// 직접 실행 시 run() 호출 (node dist/index.js)
const isMainModule =
  process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMainModule) {
  run();
}

