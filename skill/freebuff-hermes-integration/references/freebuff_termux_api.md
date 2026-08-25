# FreeBuff Termux API 레퍼런스

## 유틸리티 함수

### 환경 감지

| 함수                  | 시그니처               | 반환값                                            | 설명                              |
| --------------------- | ---------------------- | ------------------------------------------------- | --------------------------------- |
| `isTermux()`          | `() => boolean`        | Termux 환경 여부                                  | `PREFIX` 환경 변수로 감지         |
| `getTermuxPrefix()`   | `() => string`         | PREFIX 경로 또는 `''`                             | `/data/data/com.termux/files/usr` |
| `getArch()`           | `() => Architecture`   | `aarch64` / `arm` / `x86_64` / `i386` / `unknown` | CPU 아키텍처                      |
| `getAndroidVersion()` | `() => string \| null` | Android 버전 또는 null                            | `getprop`로 조회                  |
| `getStoragePath()`    | `() => string`         | `/storage/emulated/0`                             | 공유 저장소 경로                  |

### 경로 처리

| 함수                             | 시그니처                                          | 설명                                               |
| -------------------------------- | ------------------------------------------------- | -------------------------------------------------- |
| `resolvePath(path)`              | `(string) => string`                              | `/usr`와 알려진 Termux system root만 PREFIX로 변환 |
| `normalizePathForTermux(path)`   | `(string) => string`                              | `.`, `..`, `~`, 중복 슬래시 정규화                 |
| `expandTilde(path, home?)`       | `(string, string?) => string`                     | `~`를 홈 디렉토리로 확장                           |
| `termuxToProot(path, config)`    | `(string, Partial<ProotDistroConfig>) => string`  | Termux 경로 → proot 경로                           |
| `prootToTermux(path, config)`    | `(string, Partial<ProotDistroConfig>) => string`  | proot 경로 → Termux 경로                           |
| `isTermuxHomePath(path, config)` | `(string, Partial<ProotDistroConfig>) => boolean` | Termux 홈 하위 경로 여부                           |
| `buildBindMountArgs(config)`     | `(Partial<ProotDistroConfig>) => string[]`        | 검증된 custom/storage bind argv                    |

존재하지 않는 custom bind source는 실행 전에 `BindMountError`를 던지며 `code`는 `BIND_MOUNT_NOT_FOUND`다.

### 명령 확인

| 함수                                    | 시그니처                                     | 설명                            |
| --------------------------------------- | -------------------------------------------- | ------------------------------- |
| `isCommandAvailable(command, options?)` | `(string, CommandLookupOptions?) => boolean` | shell 없이 PATH에서 명령어 확인 |
| `isProotAvailable()`                    | `() => boolean`                              | proot-distro 설치 여부          |

## ProotDistroManager 클래스

### 생성자

```typescript
new ProotDistroManager(runner?: CommandRunner)
```

기본 구현은 probe와 PRoot 실행 모두 `spawnSync(command, args, { shell: false })`를 사용한다. PRoot-Distro v5 container 목록은 `list --quiet`으로 읽고 실행은 `--isolated --shared-home`으로 Android storage 자동 노출을 차단한다. 사용자 정의 runner는 구조적 실행을 위해 다음 메서드를 제공해야 한다. 문자열 `exec` 메서드는 deprecated이며 manager가 호출하지 않는다.

```typescript
execFile(command, args, options?) => ExecResult
```

### 메서드

| 메서드                                                 | 반환값                                  | 설명                                                     |
| ------------------------------------------------------ | --------------------------------------- | -------------------------------------------------------- |
| `isProotDistroInstalled()`                             | `boolean`                               | proot-distro 설치 여부                                   |
| `isDistroInstalled(distro)`                            | `boolean`                               | 특정 distro 설치 여부                                    |
| `getInstalledDistros()`                                | `string[]`                              | 설치된 distro 목록                                       |
| `installDistro(distro, image?)`                        | `ExecResult`                            | `image@sha256:<digest>`가 필수인 distro 설치             |
| `execInDistro(distro, command, config?, commandArgs?)` | `ExecResult`                            | 고정 Bash 코드와 별도 위치 인자로 distro 내부 명령 실행  |
| `installBunInDistro(distro)`                           | `ExecResult`                            | deprecated fail-closed helper. `scripts/install.sh` 사용 |
| `installFreeBuffInDistro(distro)`                      | `ExecResult`                            | deprecated fail-closed helper. `scripts/install.sh` 사용 |
| `isFreeBuffInstalled(distro)`                          | `boolean`                               | FreeBuff 설치 여부                                       |
| `runFreeBuff(distro, termuxCwd, args?, config?)`       | `FreeBuffRunResult`                     | FreeBuff 동기 실행 (`spawnSync`, shell false)            |
| `preflightCheck(distro)`                               | `{ ready: boolean, missing: string[] }` | 사전 검증                                                |
| `getDistroRootPath(distro)`                            | `string`                                | distro rootfs 경로                                       |

## FreeBuffLauncher 클래스

### 생성자

```typescript
new FreeBuffLauncher(spawner?: Spawner, preflight?: PreflightCheck)
```

`Spawner`를 생략하면 `child_process.spawn` 기반 기본 구현체와 실제 PRoot preflight를 사용한다. 테스트용 `Spawner`를 주입하면 자동 preflight는 생략되며, 필요하면 두 번째 인자로 별도 검사를 주입한다.

### 메서드

| 메서드                                                        | 반환값                 | 설명                                          |
| ------------------------------------------------------------- | ---------------------- | --------------------------------------------- |
| `buildCommand(distro, prootCwd, args, config?)`               | `[string, string[]]`   | 실행할 명령어와 인자 배열 생성                |
| `launch(distro, termuxCwd, args?, config?, controls?)`        | `Promise<SpawnResult>` | 인터랙티브 모드, AbortSignal·kill grace 지원  |
| `run(distro, termuxCwd, args?, config?, timeout?, controls?)` | `Promise<SpawnResult>` | pipe 모드, 제한 출력 캡처·timeout·AbortSignal |

기본 spawner는 Linux에서 분리된 process group 전체에 TERM을 전달하고, 기본 5초 grace 뒤 KILL로 승격한다. pipe 모드의 stdout+stderr 합산 기본 예산은 1MiB다. 직접 `Spawner`가 필요하면 공개된 `createNodeSpawner()` factory를 사용한다.

## Termux 특화 기능

### Wake Lock

| 함수                    | 반환값    | 설명                            |
| ----------------------- | --------- | ------------------------------- |
| `acquireWakeLock()`     | `boolean` | 화면 꺼짐/Doze 방지             |
| `releaseWakeLock()`     | `boolean` | Wake Lock 해제                  |
| `isWakeLockAvailable()` | `boolean` | termux-wake-lock 사용 가능 여부 |

### 저장소

| 함수                                      | 반환값    | 설명                                   |
| ----------------------------------------- | --------- | -------------------------------------- |
| `setupStorage()`                          | `boolean` | `termux-setup-storage` 실행            |
| `isStorageSetup(home?, directoryExists?)` | `boolean` | 셸 없이 `~/storage` 디렉토리 존재 여부 |

### 메모리

| 함수              | 반환값               | 설명                                          |
| ----------------- | -------------------- | --------------------------------------------- |
| `getMemoryInfo()` | `MemoryInfo \| null` | `/proc/meminfo` 파싱                          |
| `checkOomRisk()`  | `OomRiskAssessment`  | OOM 위험도 평가 (unknown/safe/caution/danger) |

## 타입 정의

### ProotDistroConfig

```typescript
interface ProotDistroConfig {
  distro: string; // 'ubuntu', 'debian' 등
  user?: string; // 기본값: 'root'
  termuxHome?: string; // 기본값: process.env.HOME
  prootHome?: string; // 기본값: '/root'
  bindMounts?: string[]; // 추가 bind mount 경로
  storageBind?: boolean; // 공유 저장소 bind, 기본값 false
}
```

### SpawnResult

```typescript
interface SpawnResult {
  exitCode: number | null; // null = 시그널 종료
  signal: NodeJS.Signals | null;
  stdout: string; // pipe 모드에서만
  stderr: string; // pipe 모드에서만
  terminationReason?: 'timeout' | 'abort' | 'output-limit';
  outputTruncated?: boolean;
}
```

### LaunchOptions

```typescript
interface LaunchOptions {
  cwd?: string;
  env?: Record<string, string>;
  stdio?: 'inherit' | 'pipe';
  timeout?: number;
  killGraceMs?: number; // 기본값 5000
  maxOutputBytes?: number; // pipe 합산 기본값 1MiB
  signal?: AbortSignal;
}
```

### OomRiskAssessment

```typescript
interface OomRiskAssessment {
  level: 'unknown' | 'safe' | 'caution' | 'danger';
  recommendedFreeKB: number; // 524288 (512MB)
  currentFreeKB: number;
  message: string;
}
```
