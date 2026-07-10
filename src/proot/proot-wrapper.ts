/**
 * proot-distro 래퍼 모듈
 *
 * B+C 하이브리드 전략의 핵심 컴포넌트.
 * proot-distro를 통해 Termux 내부에 Linux 환경을 구성하고,
 * 그 안에서 Bun 런타임과 FreeBuff CLI를 실행할 수 있도록 지원한다.
 *
 * 의존성 주입: CommandRunner 인터페이스를 통해 명령 실행기를 주입받아
 * 테스트 가능성을 확보한다.
 */

import { execSync } from 'node:child_process';
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

// ─── 기본 CommandRunner 구현체 ───────────────────────────────

/**
 * child_process.execSync를 기반으로 하는 기본 CommandRunner 구현체.
 */
const defaultCommandRunner: CommandRunner = {
  exec(command: string, options?: ExecOptions): ExecResult {
    try {
      const stdout = execSync(command, {
        encoding: 'utf-8',
        cwd: options?.cwd,
        env: { ...process.env, ...options?.env },
        timeout: options?.timeout,
        stdio: 'pipe',
      });
      return { stdout, stderr: '', exitCode: 0 };
    } catch (error: unknown) {
      const err = error as {
        stdout?: string;
        stderr?: string;
        status?: number;
      };
      return {
        stdout: err.stdout ?? '',
        stderr: err.stderr ?? String(error),
        exitCode: err.status ?? 1,
      };
    }
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
 * - Bun 런타임 및 FreeBuff CLI 설치
 * - FreeBuff 실행 (경로 브리지 자동 적용)
 */
export class ProotDistroManager {
  private runner: CommandRunner;

  constructor(runner?: CommandRunner) {
    this.runner = runner ?? defaultCommandRunner;
  }

  /**
   * proot-distro 명령어가 시스템에 설치되어 있는지 확인한다.
   */
  isProotDistroInstalled(): boolean {
    const result = this.runner.exec('command -v proot-distro');
    return result.exitCode === 0 && result.stdout.trim().length > 0;
  }

  /**
   * 지정된 distro가 proot-distro에 설치되어 있는지 확인한다.
   */
  isDistroInstalled(distro: string): boolean {
    const result = this.runner.exec(
      `proot-distro list --installed 2>/dev/null | grep -q "^${distro}$"`,
    );
    return result.exitCode === 0;
  }

  /**
   * 설치된 distro 목록을 반환한다.
   */
  getInstalledDistros(): string[] {
    const result = this.runner.exec('proot-distro list --installed');
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
  installDistro(distro: string): ExecResult {
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
    return this.runner.exec(`proot-distro install ${distro}`);
  }

  /**
   * 지정된 distro 내부에서 명령을 실행한다.
   */
  execInDistro(
    distro: string,
    command: string,
    config: Partial<ProotDistroConfig> = {},
  ): ExecResult {
    if (!this.isDistroInstalled(distro)) {
      return {
        stdout: '',
        stderr: `Distro '${distro}' is not installed.`,
        exitCode: 1,
      };
    }
    const bindArgs = buildBindMountArgs(config).join(' ');
    const userFlag = config.user ? ` --user ${config.user}` : '';
    const escapedCmd = command.replace(/'/g, "'\\''");
    const fullCmd = `proot-distro login${userFlag} ${bindArgs} ${distro} -- bash -lc '${escapedCmd}'`;
    return this.runner.exec(fullCmd);
  }

  /**
   * distro 내부에 Bun 런타임을 설치한다.
   */
  installBunInDistro(distro: string): ExecResult {
    return this.execInDistro(
      distro,
      'curl -fsSL https://bun.sh/install | bash',
    );
  }

  /**
   * distro 내부에 FreeBuff CLI를 전역 설치한다.
   */
  installFreeBuffInDistro(distro: string): ExecResult {
    const cmd =
      'export BUN_INSTALL="$HOME/.bun" && ' +
      'export PATH="$BUN_INSTALL/bin:$PATH" && ' +
      'bun install -g freebuff';
    return this.execInDistro(distro, cmd);
  }

  /**
   * FreeBuff가 distro 내부에 설치되어 있는지 확인한다.
   */
  isFreeBuffInstalled(distro: string): boolean {
    const cmd =
      'export BUN_INSTALL="$HOME/.bun" && ' +
      'export PATH="$BUN_INSTALL/bin:$PATH" && ' +
      'command -v freebuff';
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
    const escapedArgs = args
      .map((a) => `'${a.replace(/'/g, "'\\''")}'`)
      .join(' ');
    const escapedCwd = prootCwd.replace(/'/g, "'\\''");
    const cmd =
      'export BUN_INSTALL="$HOME/.bun" && ' +
      'export PATH="$BUN_INSTALL/bin:$PATH" && ' +
      `cd '${escapedCwd}' && freebuff ${escapedArgs}`;
    const result = this.execInDistro(distro, cmd, config);
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
      missing.push('freebuff (installFreeBuffInDistro)');
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
