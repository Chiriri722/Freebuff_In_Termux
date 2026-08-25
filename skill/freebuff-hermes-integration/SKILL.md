---
name: freebuff-hermes-integration
description: Hermes Agent가 FreeBuff AI 코딩 에이전트를 Termux 환경에서 호출하고 활용하는 스킬. 코드 생성, 수정, 분석 작업을 FreeBuff에 위임할 때 사용. ProotDistroManager API와 FreeBuffLauncher를 통한 실제 실행 메커니즘 제공.
---

# FreeBuff Hermes 통합

## 개요

이 스킬은 Hermes Agent가 FreeBuff AI 코딩 에이전트를 활용할 수 있도록 연동한다. FreeBuff는 Codebuff 플랫폼 기반의 무료 AI 코딩 도구로, Termux 환경에서는 proot-distro를 통해 실행된다.

## 1. 사전 조건 확인

FreeBuff 실행 전에는 설치 manager의 strict JSON 출력을 우선 사용한다.

```bash
freebuff-termux doctor --json
```

종료 코드는 `0=ok`, `1=degraded`, `2=invalid`다. JSON의 `distro`를 이후 API 호출에 사용한다. TypeScript 내부에서는 추가로 `ProotDistroManager.preflightCheck()`를 호출할 수 있다.

```typescript
import { execFileSync } from 'node:child_process';
import { ProotDistroManager } from 'freebuff-termux';

const doctorReport = JSON.parse(
  execFileSync('freebuff-termux', ['doctor', '--json'], { encoding: 'utf8' }),
);
const mgr = new ProotDistroManager();
const distro = doctorReport.distro;
const check = mgr.preflightCheck(distro);

if (!check.ready) {
  // check.missing에 누락된 항목 목록이 포함됨
  console.error('Missing dependencies:', check.missing);
  // 복구 권유: freebuff-termux repair
}
```

## 2. 인터랙티브 실행 (권장)

FreeBuff는 인터랙티브 CLI이므로 `FreeBuffLauncher.launch()`를 사용한다. stdin/stdout/stderr가 실시간으로 브리징되어 사용자가 직접 상호작용할 수 있다.

```typescript
import { FreeBuffLauncher } from 'freebuff-termux';

const launcher = new FreeBuffLauncher();
const result = await launcher.launch(
  distro, // doctor가 반환한 configured distro
  process.cwd(), // Termux 측 작업 디렉토리 (자동으로 proot 경로로 변환됨)
  [], // FreeBuff CLI 인자
  {
    termuxHome: process.env.HOME,
    prootHome: '/root',
    storageBind: false,
  },
);

console.log(`Exit code: ${result.exitCode}`);
```

경로는 자동 변환된다:

- `/data/data/com.termux/files/home/project` → `/root/project`
- `/storage/emulated/0/Documents`는 `storageBind: true`를 명시한 경우에만 유지된다.

런처는 PRoot-Distro v5를 `--isolated --shared-home`으로 실행하므로 Termux HOME만 기본 공유된다. v5의 기본 Android storage 자동 bind에 의존하지 않는다.

## 3. 프로그래밍 모드 실행

출력을 캡처하여 후속 처리가 필요한 경우 `run()` 메서드를 사용한다.

```typescript
const result = await launcher.run(
  distro,
  '/data/data/com.termux/files/home/my-project',
  ['--prompt', 'Add error handling to all API endpoints'],
  { termuxHome: process.env.HOME },
  60000, // 60초 타임아웃
);

// result.stdout에 FreeBuff 출력이 캡처됨
// result.exitCode로 성공 여부 판단
```

## 4. Termux 환경 최적화

장시간 실행 시 다음 기능을 사용한다:

```typescript
import {
  acquireWakeLock,
  checkOomRisk,
  releaseWakeLock,
} from 'freebuff-termux';

// 1. OOM 위험도 사전 확인
const oom = checkOomRisk();
if (oom.level === 'unknown') {
  console.error('Memory status is unknown:', oom.message);
  return;
}
if (oom.level === 'danger') {
  console.error(oom.message);
  return; // 실행 중단
}

// 2. Wake Lock 획득 (화면 꺼짐 방지)
acquireWakeLock();

try {
  // 3. FreeBuff 실행
  await launcher.launch(distro, cwd, []);
} finally {
  // 4. Wake Lock 해제
  releaseWakeLock();
}
```

## 5. 파일 수정 워크플로우

Hermes Agent가 FreeBuff를 사용하여 파일을 수정하는 워크플로우:

1. **문제 분석**: 수정이 필요한 파일 식별
2. **사전 검증**: `preflightCheck()`로 환경 확인
3. **OOM 체크**: `checkOomRisk()`로 메모리 확인
4. **Wake Lock**: `acquireWakeLock()`으로 백그라운드 실행 보장
5. **FreeBuff 실행**: `launcher.launch()`로 인터랙티브 실행
6. **결과 검토**: FreeBuff 출력 확인, 필요시 추가 지시
7. **정리**: `releaseWakeLock()`으로 Wake Lock 해제

공유 저장소 프로젝트가 반드시 필요하면 storage 권한을 먼저 확인하고 다음과 같이 명시적으로 opt-in한다.

```typescript
await launcher.launch(distro, storageProject, [], {
  termuxHome: process.env.HOME,
  prootHome: '/root',
  storageBind: true,
});
```

## 리소스

- `references/freebuff_termux_api.md` — 전체 API 레퍼런스
- `scripts/health_check.sh` — Termux 환경 건강 검사 스크립트
