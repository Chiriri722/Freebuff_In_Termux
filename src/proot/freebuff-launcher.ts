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
import {
  assertSafeIdentifier,
  FREEBUFF_EXECUTABLE,
  FREEBUFF_RUNTIME_PATH,
} from './command-spec.js';
import { termuxToProot, buildBindMountArgs } from './path-bridge.js';
import { ProotDistroManager } from './proot-wrapper.js';

// ─── 기본 Spawner 구현체 ─────────────────────────────────────

/**
 * child_process.spawn을 기반으로 하는 기본 Spawner 구현체.
 */
const DEFAULT_MAX_OUTPUT_BYTES = 1024 * 1024;
const DEFAULT_KILL_GRACE_MS = 5000;

type SpawnProcess = typeof spawn;
type ProcessKiller = (pid: number, signal: NodeJS.Signals) => boolean;
type ProcessSignalTarget = {
  on(event: 'SIGINT' | 'SIGTERM', listener: () => void): unknown;
  removeListener(event: 'SIGINT' | 'SIGTERM', listener: () => void): unknown;
};

export const createNodeSpawner = (
  spawnProcess: SpawnProcess = spawn,
  platform: NodeJS.Platform = process.platform,
  killProcess: ProcessKiller = process.kill,
  signalTarget: ProcessSignalTarget = process,
): Spawner => ({
  spawn(
    command: string,
    args: string[],
    options?: LaunchOptions,
  ): Promise<SpawnResult> {
    const stdioMode = options?.stdio ?? 'inherit';
    const maxOutputBytes =
      stdioMode === 'pipe'
        ? (options?.maxOutputBytes ?? DEFAULT_MAX_OUTPUT_BYTES)
        : 0;
    const killGraceMs = options?.killGraceMs ?? DEFAULT_KILL_GRACE_MS;

    if (
      stdioMode === 'pipe' &&
      (!Number.isSafeInteger(maxOutputBytes) || maxOutputBytes <= 0)
    ) {
      throw new RangeError('maxOutputBytes must be a positive integer');
    }
    if (!Number.isSafeInteger(killGraceMs) || killGraceMs < 0) {
      throw new RangeError('killGraceMs must be a non-negative integer');
    }
    if (
      options?.timeout !== undefined &&
      (!Number.isSafeInteger(options.timeout) || options.timeout < 0)
    ) {
      throw new RangeError('timeout must be a non-negative integer');
    }
    if (options?.signal?.aborted) {
      return Promise.resolve({
        exitCode: null,
        signal: null,
        stdout: '',
        stderr: '',
        terminationReason: 'abort',
      });
    }

    return new Promise((resolve, reject) => {
      const child = spawnProcess(command, args, {
        cwd: options?.cwd,
        env: { ...process.env, ...options?.env },
        stdio: stdioMode,
        shell: false,
        detached: platform !== 'win32',
      });

      const stdoutChunks: Buffer[] = [];
      const stderrChunks: Buffer[] = [];
      let capturedBytes = 0;
      let outputTruncated = false;
      let terminationReason: SpawnResult['terminationReason'];
      let settled = false;
      let timeoutTimer: NodeJS.Timeout | undefined;
      let forceKillTimer: NodeJS.Timeout | undefined;

      const signalChild = (signal: NodeJS.Signals) => {
        if (platform !== 'win32' && child.pid) {
          try {
            killProcess(-child.pid, signal);
            return;
          } catch {
            // Process group may already be gone; fall back to the direct child.
          }
        }
        child.kill(signal);
      };

      const scheduleForceKill = () => {
        if (settled || forceKillTimer) return;
        if (killGraceMs === 0) {
          signalChild('SIGKILL');
        } else {
          forceKillTimer = setTimeout(
            () => signalChild('SIGKILL'),
            killGraceMs,
          );
        }
      };

      const requestTermination = (
        reason: NonNullable<SpawnResult['terminationReason']>,
      ) => {
        if (settled || terminationReason) return;
        terminationReason = reason;
        signalChild('SIGTERM');
        scheduleForceKill();
      };

      const capture = (chunks: Buffer[], value: Buffer | string) => {
        if (outputTruncated) return;
        const data = Buffer.isBuffer(value) ? value : Buffer.from(value);
        const remaining = maxOutputBytes - capturedBytes;
        if (data.length <= remaining) {
          chunks.push(data);
          capturedBytes += data.length;
          return;
        }
        if (remaining > 0) chunks.push(data.subarray(0, remaining));
        capturedBytes = maxOutputBytes;
        outputTruncated = true;
        requestTermination('output-limit');
      };

      if (stdioMode === 'pipe') {
        child.stdout?.on('data', (data: Buffer) => capture(stdoutChunks, data));
        child.stderr?.on('data', (data: Buffer) => capture(stderrChunks, data));
      }

      if (options?.timeout && options.timeout > 0) {
        timeoutTimer = setTimeout(
          () => requestTermination('timeout'),
          options.timeout,
        );
      }

      // Node process signal listeners receive no signal-name argument, so each
      // event needs a dedicated closure to preserve the exact signal.
      const forwardHostSignal = (signal: 'SIGINT' | 'SIGTERM') => {
        if (settled) return;
        signalChild(signal);
        scheduleForceKill();
      };
      const sigintHandler = () => forwardHostSignal('SIGINT');
      const sigtermHandler = () => forwardHostSignal('SIGTERM');
      const abortHandler = () => requestTermination('abort');
      signalTarget.on('SIGINT', sigintHandler);
      signalTarget.on('SIGTERM', sigtermHandler);
      options?.signal?.addEventListener('abort', abortHandler, { once: true });
      if (options?.signal?.aborted) abortHandler();

      const cleanup = () => {
        if (timeoutTimer) clearTimeout(timeoutTimer);
        if (forceKillTimer) clearTimeout(forceKillTimer);
        signalTarget.removeListener('SIGINT', sigintHandler);
        signalTarget.removeListener('SIGTERM', sigtermHandler);
        options?.signal?.removeEventListener('abort', abortHandler);
      };

      child.on('close', (code, signal) => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve({
          exitCode: code,
          signal: signal,
          stdout: Buffer.concat(stdoutChunks).toString(),
          stderr: Buffer.concat(stderrChunks).toString(),
          ...(terminationReason ? { terminationReason } : {}),
          ...(outputTruncated ? { outputTruncated: true } : {}),
        });
      });

      child.on('error', (err) => {
        if (settled) return;
        settled = true;
        cleanup();
        reject(err);
      });
    });
  },
});

const defaultSpawner: Spawner = createNodeSpawner();

export type PreflightCheck = (distro: string) => {
  ready: boolean;
  missing: string[];
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
  private preflight?: PreflightCheck;

  constructor(spawner?: Spawner, preflight?: PreflightCheck) {
    this.spawner = spawner ?? defaultSpawner;
    if (preflight) {
      this.preflight = preflight;
    } else if (!spawner) {
      const manager = new ProotDistroManager();
      this.preflight = (distro) => manager.preflightCheck(distro);
    }
  }

  private assertReady(distro: string): void {
    const result = this.preflight?.(distro);
    if (result && !result.ready) {
      throw new Error(`Preflight failed: ${result.missing.join(', ')}`);
    }
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
    config: Partial<ProotDistroConfig> = {},
  ): [string, string[]] {
    assertSafeIdentifier(distro, 'distro');
    if (config.user) assertSafeIdentifier(config.user, 'user');

    const bindArgs = buildBindMountArgs(config);
    const userFlag = config.user ? ['--user', config.user] : [];

    // 사용자 입력은 이 스크립트에 보간하지 않고 bash의 위치 인자로 전달한다.
    const shellCommand =
      `export PATH="${FREEBUFF_RUNTIME_PATH}:$PATH"; ` +
      `cd -- "$1"; shift; exec ${FREEBUFF_EXECUTABLE} "$@"`;

    // proot-distro login 인자 구성
    const loginArgs = [
      'login',
      ...userFlag,
      '--isolated',
      '--shared-home',
      ...bindArgs,
      distro,
      '--',
      '/bin/bash',
      '--norc',
      '--noprofile',
      '-c',
      shellCommand,
      '--',
      prootCwd,
      ...freebuffArgs,
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
    config: Partial<ProotDistroConfig> = {},
    controls: Pick<LaunchOptions, 'signal' | 'killGraceMs'> = {},
  ): Promise<SpawnResult> {
    this.assertReady(distro);
    const prootCwd = termuxToProot(termuxCwd, config);
    const [command, commandArgs] = this.buildCommand(
      distro,
      prootCwd,
      args,
      config,
    );

    return this.spawner.spawn(command, commandArgs, {
      ...config,
      ...controls,
      stdio: 'inherit',
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
    timeout: number = 0,
    controls: Pick<
      LaunchOptions,
      'signal' | 'killGraceMs' | 'maxOutputBytes'
    > = {},
  ): Promise<SpawnResult> {
    this.assertReady(distro);
    const prootCwd = termuxToProot(termuxCwd, config);
    const [command, commandArgs] = this.buildCommand(
      distro,
      prootCwd,
      args,
      config,
    );

    return this.spawner.spawn(command, commandArgs, {
      ...config,
      ...controls,
      stdio: 'pipe',
      timeout: timeout || undefined,
    });
  }
}
