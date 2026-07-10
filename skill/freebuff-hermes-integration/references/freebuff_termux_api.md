# FreeBuff Termux API 레퍼런스

## 유틸리티 함수

### 환경 감지

| 함수 | 시그니처 | 반환값 | 설명 |
|------|----------|--------|------|
| `isTermux()` | `() => boolean` | Termux 환경 여부 | `PREFIX` 환경 변수로 감지 |
| `getTermuxPrefix()` | `() => string` | PREFIX 경로 또는 `''` | `/data/data/com.termux/files/usr` |
| `getArch()` | `() => Architecture` | `aarch64` / `arm` / `x86_64` / `i386` / `unknown` | CPU 아키텍처 |
| `getAndroidVersion()` | `() => string \| null` | Android 버전 또는 null | `getprop`로 조회 |
| `getStoragePath()` | `() => string` | `/storage/emulated/0` | 공유 저장소 경로 |

### 경로 처리

| 함수 | 시그니처 | 설명 |
|------|----------|------|
| `resolvePath(path)` | `(string) => string` | 절대 경로에 Termux PREFIX 추가 |
| `normalizePathForTermux(path)` | `(string) => string` | `.`, `..`, `~`, 중복 슬래시 정규화 |
| `expandTilde(path, home?)` | `(string, string?) => string` | `~`를 홈 디렉토리로 확장 |
| `termuxToProot(path, config)` | `(string, Partial<ProotDistroConfig>) => string` | Termux 경로 → proot 경로 |
| `prootToTermux(path, config)` | `(string, Partial<ProotDistroConfig>) => string` | proot 경로 → Termux 경로 |
| `isTermuxHomePath(path, config)` | `(string, Partial<ProotDistroConfig>) => boolean` | Termux 홈 하위 경로 여부 |

### 명령 확인

| 함수 | 시그니처 | 설명 |
|------|----------|------|
| `isCommandAvailable(command)` | `(string) => boolean` | 명령어 존재 확인 (크로스 플랫폼) |
| `isProotAvailable()` | `() => boolean` | proot-distro 설치 여부 |

## ProotDistroManager 클래스

### 생성자

```typescript
new ProotDistroManager(runner?: CommandRunner)
```

`CommandRunner`를 생략하면 `child_process.execSync` 기반 기본 구현체 사용.

### 메서드

| 메서드 | 반환값 | 설명 |
|--------|--------|------|
| `isProotDistroInstalled()` | `boolean` | proot-distro 설치 여부 |
| `isDistroInstalled(distro)` | `boolean` | 특정 distro 설치 여부 |
| `getInstalledDistros()` | `string[]` | 설치된 distro 목록 |
| `installDistro(distro)` | `ExecResult` | distro 설치 |
| `execInDistro(distro, command, config?)` | `ExecResult` | distro 내부 명령 실행 |
| `installBunInDistro(distro)` | `ExecResult` | Bun 런타임 설치 |
| `installFreeBuffInDistro(distro)` | `ExecResult` | FreeBuff CLI 설치 |
| `isFreeBuffInstalled(distro)` | `boolean` | FreeBuff 설치 여부 |
| `runFreeBuff(distro, termuxCwd, args?, config?)` | `FreeBuffRunResult` | FreeBuff 동기 실행 (execSync 기반) |
| `preflightCheck(distro)` | `{ ready: boolean, missing: string[] }` | 사전 검증 |
| `getDistroRootPath(distro)` | `string` | distro rootfs 경로 |

## FreeBuffLauncher 클래스

### 생성자

```typescript
new FreeBuffLauncher(spawner?: Spawner)
```

`Spawner`를 생략하면 `child_process.spawn` 기반 기본 구현체 사용.

### 메서드

| 메서드 | 반환값 | 설명 |
|--------|--------|------|
| `buildCommand(distro, prootCwd, args, config?)` | `[string, string[]]` | 실행할 명령어와 인자 배열 생성 |
| `launch(distro, termuxCwd, args?, config?)` | `Promise<SpawnResult>` | 인터랙티브 모드 (stdio: inherit) |
| `run(distro, termuxCwd, args?, config?, timeout?)` | `Promise<SpawnResult>` | 프로그래밍 모드 (stdio: pipe, 출력 캡처) |

## Termux 특화 기능

### Wake Lock

| 함수 | 반환값 | 설명 |
|------|--------|------|
| `acquireWakeLock()` | `boolean` | 화면 꺼짐/Doze 방지 |
| `releaseWakeLock()` | `boolean` | Wake Lock 해제 |
| `isWakeLockAvailable()` | `boolean` | termux-wake-lock 사용 가능 여부 |

### 저장소

| 함수 | 반환값 | 설명 |
|------|--------|------|
| `setupStorage()` | `boolean` | `termux-setup-storage` 실행 |
| `isStorageSetup()` | `boolean` | `~/storage` 디렉토리 존재 여부 |

### 메모리

| 함수 | 반환값 | 설명 |
|------|--------|------|
| `getMemoryInfo()` | `MemoryInfo \| null` | `/proc/meminfo` 파싱 |
| `checkOomRisk()` | `OomRiskAssessment` | OOM 위험도 평가 (safe/caution/danger) |

## 타입 정의

### ProotDistroConfig

```typescript
interface ProotDistroConfig {
  distro: string;        // 'ubuntu', 'debian' 등
  user?: string;         // 기본값: 'root'
  termuxHome?: string;   // 기본값: process.env.HOME
  prootHome?: string;    // 기본값: '/root'
  bindMounts?: string[]; // 추가 bind mount 경로
}
```

### SpawnResult

```typescript
interface SpawnResult {
  exitCode: number | null;      // null = 시그널 종료
  signal: NodeJS.Signals | null;
  stdout: string;               // pipe 모드에서만
  stderr: string;               // pipe 모드에서만
}
```

### OomRiskAssessment

```typescript
interface OomRiskAssessment {
  level: 'safe' | 'caution' | 'danger';
  recommendedFreeKB: number;    // 524288 (512MB)
  currentFreeKB: number;
  message: string;
}
```
