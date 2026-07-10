/**
 * FreeBuff Termux 변환 레이어 — 공유 타입 정의
 *
 * proot-distro 래퍼, 경로 브리지, 명령 실행기 등에서
 * 공통으로 사용하는 인터페이스와 타입을 정의한다.
 */

/** 실행 결과를 나타내는 표준 인터페이스 */
export interface ExecResult {
  /** 표준 출력 */
  stdout: string;
  /** 표준 에러 */
  stderr: string;
  /** 종료 코드 (0 = 성공) */
  exitCode: number;
}

/** 명령 실행 옵션 */
export interface ExecOptions {
  /** 작업 디렉토리 */
  cwd?: string;
  /** 환경 변수 (기존 process.env에 병합됨) */
  env?: Record<string, string>;
  /** 타임아웃 (밀리초) */
  timeout?: number;
}

/**
 * 명령 실행기 인터페이스.
 * proot-wrapper의 테스트 가능성을 위해 추상화한다.
 * 실제 환경에서는 child_process 기반 구현체를 사용하고,
 * 테스트에서는 mock 구현체를 주입한다.
 */
export interface CommandRunner {
  /** 동기식 명령 실행 */
  exec(command: string, options?: ExecOptions): ExecResult;
}

/** CPU 아키텍처 타입 */
export type Architecture =
  | 'aarch64'
  | 'arm'
  | 'x86_64'
  | 'i386'
  | 'unknown';

/** proot-distro 설정 */
export interface ProotDistroConfig {
  /** distro 이름 (예: 'ubuntu', 'debian') */
  distro: string;
  /** distro 내 사용자 (기본값: 'root') */
  user?: string;
  /** Termux 홈 디렉토리 (기본값: process.env.HOME) */
  termuxHome?: string;
  /** proot 내 홈 디렉토리 (기본값: '/root') */
  prootHome?: string;
  /** 추가 bind mount 경로 목록 */
  bindMounts?: string[];
}

/** proot-distro 실행 결과에 경로 변환 정보를 추가한 결과 */
export interface FreeBuffRunResult extends ExecResult {
  /** Termux 측 작업 디렉토리 (변환 전) */
  termuxCwd: string;
  /** proot 측 작업 디렉토리 (변환 후) */
  prootCwd: string;
}
