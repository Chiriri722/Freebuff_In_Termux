/**
 * proot-distro 래퍼 모듈
 *
 * B+C 하이브리드 전략의 핵심 컴포넌트.
 * proot-distro를 통해 Termux 내부에 Linux 환경을 구성하고,
 * 그 안에서 검증된 Node.js 런타임과 FreeBuff CLI를 실행하도록 지원한다.
 *
 * 의존성 주입: CommandRunner 인터페이스를 통해 명령 실행기를 주입받아
 * 테스트 가능성을 확보한다.
 */

import { spawnSync } from 'node:child_process';
import type {
  CommandRunner,
  ExecResult,
  ExecOptions,
  ProotDistroConfig,
  FreeBuffRunResult,
} from '../types.js';
import {
  termuxToProot,
  buildBindMountArgs,
  getProotRootPath,
} from './path-bridge.js';
import {
  assertPinnedImageReference,
  assertSafeIdentifier,
  FREEBUFF_EXECUTABLE,
  FREEBUFF_RUNTIME_PATH,
} from './command-spec.js';

// ─── 기본 CommandRunner 구현체 ───────────────────────────────

/**
 * child_process.spawnSync를 기반으로 하는 shell-free CommandRunner 구현체.
 */
const defaultCommandRunner: CommandRunner = {
  execFile(command: string, args: string[], options?: ExecOptions): ExecResult {
    const result = spawnSync(command, args, {
      encoding: 'utf-8',
      cwd: options?.cwd,
      env: { ...process.env, ...options?.env },
      timeout: options?.timeout,
      stdio: 'pipe',
      shell: false,
    });
    return {
      stdout: result.stdout ?? '',
      stderr: result.stderr || result.error?.message || '',
      exitCode: result.status ?? 1,
    };
  },
};

// ─── ProotDistroManager 클래스 ──────────────────────────────

/**
 * proot-distro를 관리하는 매니저 클래스.
 *
 * 주요 기능:
 * - proot-distro 설치 여부 확인
 * - Linux distro 설치/삭제
 * - distro 내부에서 명령 실행
 * - 설치 상태 점검과 canonical installer 안내
 * - FreeBuff 실행 (경로 브리지 자동 적용)
 */
export class ProotDistroManager {
  private runner: CommandRunner;

  constructor(runner?: CommandRunner) {
    this.runner = runner ?? defaultCommandRunner;
  }

  private execFile(
    command: string,
    args: string[],
    options?: ExecOptions,
  ): ExecResult {
    if (!this.runner.execFile) {
      return {
        stdout: '',
        stderr:
          'CommandRunner.execFile is required for shell-free command execution.',
        exitCode: 1,
      };
    }
    return this.runner.execFile(command, args, options);
  }

  /**
   * proot-distro 명령어가 시스템에 설치되어 있는지 확인한다.
   */
  isProotDistroInstalled(): boolean {
    return this.execFile('proot-distro', ['--help']).exitCode === 0;
  }

  /**
   * 지정된 distro가 proot-distro에 설치되어 있는지 확인한다.
   */
  isDistroInstalled(distro: string): boolean {
    assertSafeIdentifier(distro, 'distro');
    return this.getInstalledDistros().includes(distro);
  }

  /**
   * 설치된 distro 목록을 반환한다.
   */
  getInstalledDistros(): string[] {
    const result = this.execFile('proot-distro', ['list', '--quiet']);
    if (result.exitCode !== 0) {
      return [];
    }
    return result.stdout
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.length > 0);
  }

  /**
   * 새로운 Linux distro를 설치한다.
   */
  installDistro(distro: string, image?: string): ExecResult {
    assertSafeIdentifier(distro, 'distro');
    if (!this.isProotDistroInstalled()) {
      return {
        stdout: '',
        stderr: 'proot-distro is not installed. Run: pkg install proot-distro',
        exitCode: 1,
      };
    }
    if (this.isDistroInstalled(distro)) {
      return {
        stdout: `Distro '${distro}' is already installed.`,
        stderr: '',
        exitCode: 0,
      };
    }
    if (!image) {
      return {
        stdout: '',
        stderr:
          'A digest-pinned image is required. Use image@sha256:<64 lowercase hex characters>.',
        exitCode: 1,
      };
    }
    assertPinnedImageReference(image);
    return this.execFile('proot-distro', ['install', '--name', distro, image]);
  }

  /**
   * 지정된 distro 내부에서 명령을 실행한다.
   */
  execInDistro(
    distro: string,
    command: string,
    config: Partial<ProotDistroConfig> = {},
    commandArgs: string[] = [],
  ): ExecResult {
    assertSafeIdentifier(distro, 'distro');
    if (config.user) assertSafeIdentifier(config.user, 'user');

    if (!this.isDistroInstalled(distro)) {
      return {
        stdout: '',
        stderr: `Distro '${distro}' is not installed.`,
        exitCode: 1,
      };
    }
    const bindArgs = buildBindMountArgs(config);
    const userFlag = config.user ? ['--user', config.user] : [];
    return this.execFile('proot-distro', [
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
      command,
      '--',
      ...commandArgs,
    ]);
  }

  /**
   * @deprecated mutable `curl | bash` 설치를 제거했다. canonical installer를 사용한다.
   */
  installBunInDistro(distro: string): ExecResult {
    assertSafeIdentifier(distro, 'distro');
    return {
      stdout: '',
      stderr:
        'Legacy Bun installation is disabled. Run the pinned scripts/install.sh workflow.',
      exitCode: 1,
    };
  }

  /**
   * @deprecated unpinned package installation을 제거했다. canonical installer를 사용한다.
   */
  installFreeBuffInDistro(distro: string): ExecResult {
    assertSafeIdentifier(distro, 'distro');
    return {
      stdout: '',
      stderr:
        'Legacy FreeBuff installation is disabled. Run the pinned scripts/install.sh workflow.',
      exitCode: 1,
    };
  }

  /**
   * FreeBuff가 distro 내부에 설치되어 있는지 확인한다.
   */
  isFreeBuffInstalled(distro: string): boolean {
    const cmd = `export PATH="${FREEBUFF_RUNTIME_PATH}:$PATH"; command -v freebuff`;
    const result = this.execInDistro(distro, cmd);
    return result.exitCode === 0 && result.stdout.trim().length > 0;
  }

  /**
   * distro 내부에서 FreeBuff를 실행한다.
   * Termux 경로는 자동으로 proot 경로로 변환된다.
   */
  runFreeBuff(
    distro: string,
    termuxCwd: string,
    args: string[] = [],
    config: Partial<ProotDistroConfig> = {},
  ): FreeBuffRunResult {
    const prootCwd = termuxToProot(termuxCwd, config);
    const cmd =
      `export PATH="${FREEBUFF_RUNTIME_PATH}:$PATH"; ` +
      `cd -- "$1"; shift; exec ${FREEBUFF_EXECUTABLE} "$@"`;
    const result = this.execInDistro(distro, cmd, config, [prootCwd, ...args]);
    return { ...result, termuxCwd, prootCwd };
  }

  /**
   * FreeBuff 실행에 필요한 모든 구성 요소가 준비되었는지 사전 검증한다.
   */
  preflightCheck(distro: string): { ready: boolean; missing: string[] } {
    const missing: string[] = [];
    if (!this.isProotDistroInstalled()) {
      missing.push('proot-distro (pkg install proot-distro)');
    }
    if (!this.isDistroInstalled(distro)) {
      missing.push(`distro '${distro}' (proot-distro install ${distro})`);
    }
    if (missing.length === 0 && !this.isFreeBuffInstalled(distro)) {
      missing.push('freebuff (run the pinned scripts/install.sh workflow)');
    }
    return { ready: missing.length === 0, missing };
  }

  /**
   * proot distro의 파일 시스템 루트 경로를 반환한다.
   */
  getDistroRootPath(distro: string): string {
    return getProotRootPath(distro);
  }
}
