/**
 * FreeBuff 인터랙티브 런처
 *
 * Phase 3A: proot-wrapper의 runFreeBuff(execSync 기반)를 보완하여
 * spawn 기반의 실시간 스트리밍 런처를 제공한다.
 *
 * FreeBuff는 인터랙티브 CLI이므로 사용자의 stdin 입력과
 * FreeBuff의 stdout/stderr 출력을 실시간으로 브리징해야 한다.
 * execSync는 모든 출력을 버퍼링하므로 인터랙티브 사용이 불가능하며,
 * 이 런처는 spawn을 사용하여 실시간 I/O를 지원한다.
 */

import { spawn } from 'node:child_process';
import type {
  Spawner,
  SpawnResult,
  LaunchOptions,
  ProotDistroConfig,
} from '../types.js';
import { termuxToProot, buildBindMountArgs } from './path-bridge.js';

// ─── 기본 Spawner 구현체 ─────────────────────────────────────

/**
 * child_process.spawn을 기반으로 하는 기본 Spawner 구현체.
 */
const defaultSpawner: Spawner = {
  spawn(
    command: string,
    args: string[],
    options?: LaunchOptions
  ): Promise<SpawnResult> {
    return new Promise((resolve, reject) => {
      const stdioMode = options?.stdio ?? 'inherit';
      const child = spawn(command, args, {
        cwd: options?.cwd,
        env: { ...process.env, ...options?.env },
        stdio: stdioMode,
        shell: false,
      });

      let stdout = '';
      let stderr = '';

      if (stdioMode === 'pipe') {
        child.stdout?.on('data', (data: Buffer) => {
          stdout += data.toString();
        });
        child.stderr?.on('data', (data: Buffer) => {
          stderr += data.toString();
        });
      }

      // 타임아웃 처리
      let timer: NodeJS.Timeout | undefined;
      if (options?.timeout && options.timeout > 0) {
        timer = setTimeout(() => {
          child.kill('SIGTERM');
          setTimeout(() => child.kill('SIGKILL'), 5000);
        }, options.timeout);
      }

      // SIGINT/SIGTERM을 자식 프로세스에 전달
      const signalHandler = (sig: NodeJS.Signals) => {
        child.kill(sig);
      };
      process.on('SIGINT', signalHandler);
      process.on('SIGTERM', signalHandler);

      child.on('close', (code, signal) => {
        if (timer) clearTimeout(timer);
        process.removeListener('SIGINT', signalHandler);
        process.removeListener('SIGTERM', signalHandler);
        resolve({
          exitCode: code,
          signal: signal,
          stdout,
          stderr,
        });
      });

      child.on('error', (err) => {
        if (timer) clearTimeout(timer);
        process.removeListener('SIGINT', signalHandler);
        process.removeListener('SIGTERM', signalHandler);
        reject(err);
      });
    });
  },
};

// ─── FreeBuffLauncher 클래스 ────────────────────────────────

/**
 * FreeBuff를 인터랙티브 모드로 실행하는 런처 클래스.
 *
 * 주요 기능:
 * - proot-distro 환경에서 FreeBuff를 spawn 기반으로 실행
 * - stdin/stdout/stderr 실시간 브리징 (인터랙티브 모드)
 * - SIGINT/SIGTERM 시그널 전달로 안전한 종료
 * - 타임아웃 지원
 * - 사전 검증 (preflightCheck) 후 실행
 */
export class FreeBuffLauncher {
  private spawner: Spawner;

  constructor(spawner?: Spawner) {
    this.spawner = spawner ?? defaultSpawner;
  }

  /**
   * proot-distro login 명령어의 인자 배열을 생성한다.
   * (테스트 및 디버깅용으로 공개)
   *
   * @param distro - distro 이름
   * @param prootCwd - proot 내부 작업 디렉토리
   * @param freebuffArgs - FreeBuff에 전달할 인자
   * @param config - proot 설정
   * @returns [command, args] 튜플
   */
  buildCommand(
    distro: string,
    prootCwd: string,
    freebuffArgs: string[],
    config: Partial<ProotDistroConfig> = {}
  ): [string, string[]] {
    const bindArgs = buildBindMountArgs(config);
    const userFlag = config.user ? ['--user', config.user] : [];

    // proot-distro login 인자 구성
    const loginArgs = [
      'login',
      ...userFlag,
      ...bindArgs,
      distro,
      '--',
      'bash',
      '-lc',
      // Bun 환경 로드 + cd + freebuff 실행
      `export BUN_INSTALL="$HOME/.bun" && ` +
        `export PATH="$BUN_INSTALL/bin:$PATH" && ` +
        `cd '${prootCwd.replace(/'/g, "'\\''")}' && ` +
        `freebuff ${freebuffArgs.map((a) => `'${a.replace(/'/g, "'\\''")}'`).join(' ')}`,
    ];

    return ['proot-distro', loginArgs];
  }

  /**
   * FreeBuff를 인터랙티브 모드로 실행한다.
   * stdin/stdout/stderr가 직접 연결되어 사용자가 실시간으로 상호작용할 수 있다.
   *
   * @param distro - distro 이름
   * @param termuxCwd - Termux 측 작업 디렉토리
   * @param args - FreeBuff에 전달할 인자 배열
   * @param config - proot 설정
   * @returns 실행 결과 (exitCode, signal)
   */
  async launch(
    distro: string,
    termuxCwd: string,
    args: string[] = [],
    config: Partial<ProotDistroConfig> = {}
  ): Promise<SpawnResult> {
    const prootCwd = termuxToProot(termuxCwd, config);
    const [command, commandArgs] = this.buildCommand(
      distro,
      prootCwd,
      args,
      config
    );

    return this.spawner.spawn(command, commandArgs, {
      stdio: 'inherit',
      ...config,
    });
  }

  /**
   * FreeBuff를 프로그래밍 모드로 실행한다.
   * stdout/stderr가 캡처되어 결과 객체로 반환된다.
   * (CI/CD나 자동화 스크립트에서 사용)
   *
   * @param distro - distro 이름
   * @param termuxCwd - Termux 측 작업 디렉토리
   * @param args - FreeBuff에 전달할 인자 배열
   * @param config - proot 설정
   * @param timeout - 타임아웃 (밀리초, 0 = 무제한)
   * @returns 실행 결과 (exitCode, signal, stdout, stderr)
   */
  async run(
    distro: string,
    termuxCwd: string,
    args: string[] = [],
    config: Partial<ProotDistroConfig> = {},
    timeout: number = 0
  ): Promise<SpawnResult> {
    const prootCwd = termuxToProot(termuxCwd, config);
    const [command, commandArgs] = this.buildCommand(
      distro,
      prootCwd,
      args,
      config
    );

    return this.spawner.spawn(command, commandArgs, {
      stdio: 'pipe',
      timeout: timeout || undefined,
      ...config,
    });
  }
}
