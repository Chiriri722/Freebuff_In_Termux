# FreeBuff in Termux

> **도구 타입**: Termux/Android 호환 레이어 | **대상**: Bun 기반 CLI 도구 | **전략**: B+C 하이브리드

[FreeBuff](https://www.npmjs.com/package/freebuff)는 [Codebuff](https://github.com/CodebuffAI/codebuff) 플랫폼 기반의 무료 AI 코딩 에이전트입니다. FreeBuff는 **Bun 런타임**으로 컴파일된 단일 바이너리로 배포되며, Bun은 현재 **Termux/Android에서 실행할 수 없습니다** ([oven-sh/bun#5085](https://github.com/oven-sh/bun/issues/5085)).

이 프로젝트는 **B+C 하이브리드 전략**으로 이 문제를 해결합니다:

| 전략 | 구성 요소 | 역할 |
|------|-----------|------|
| **B** | proot-distro (Ubuntu) | Bun 실행 가능한 Linux 환경 제공 |
| **C** | 경로 브리지 (path-bridge) | Termux ↔ proot 간 파일 경로 자동 변환 |

```
Termux (Android)
├── freebuff 명령어 → wrapper 스크립트
├── 경로 변환: ~/project → /root/project (proot)
└── proot-distro login ubuntu
    ├── Bun 런타임 설치
    └── freebuff CLI 실행 (Bun 바이너리)
```

## 사전 요구사항 (Prerequisites)

| 요구사항 | 필수 | 설명 |
|----------|------|------|
| **Termux** | ✅ | [F-Droid](https://f-droid.org/packages/com.termux/)에서 설치 권장 (Play Store 버전은 구버전) |
| **proot-distro** | ✅ | 설치 시 자동 설치됨 |
| **Node.js** | ✅ | Termux 내 Node.js (freebuff 런처용) |
| **Bun** | ✅ | proot-distro 내부에 자동 설치됨 |
| **storage 권한** | ✅ | `termux-setup-storage` 실행 필요 (Android 파일 접근용) |

> **참고**: 이 프로젝트는 **Bun이 Termux에서 실행 불가**한 문제를 해결하기 위해 만들어졌습니다.
> Bun이 지원되면 이 호환 레이어는 더 이상 필요하지 않습니다.

## 빠른 시작

### 원라인 설치 (권장)

Termux에서 다음 명령어 한 줄로 전체 설치가 가능합니다:

```bash
curl -fsSL https://raw.githubusercontent.com/Chiriri722/Freebuff_In_Termux/main/scripts/remote-install.sh | bash
```

다른 distro(debian 등)를 사용하려면:

```bash
curl -fsSL https://raw.githubusercontent.com/Chiriri722/Freebuff_In_Termux/main/scripts/remote-install.sh | bash -s -- debian
```

설치 후 쉘을 재시작하거나 `source ~/.bashrc`를 실행한 뒤:

```bash
cd ~/my-project
freebuff
```

### 수동 설치 (개발자용)

```bash
# 저장소 클론
git clone https://github.com/Chiriri722/Freebuff_In_Termux.git
cd Freebuff_In_Termux

# 설치 스크립트 실행 (Ubuntu distro 사용)
bash scripts/install.sh

# 쉘 재시작 또는 source
source ~/.bashrc

# FreeBuff 실행
cd ~/my-project
freebuff
```

### TypeScript 라이브러리로 사용

```bash
npm install
npm run build
```

```typescript
import { ProotDistroManager, isTermux, resolvePath } from 'freebuff-termux';

if (isTermux()) {
  const mgr = new ProotDistroManager();
  
  // 사전 검증
  const check = mgr.preflightCheck('ubuntu');
  if (!check.ready) {
    console.error('Missing:', check.missing);
  }
  
  // FreeBuff 실행 (경로 자동 변환)
  const result = mgr.runFreeBuff('ubuntu', process.cwd(), []);
  console.log(result.stdout);
}
```

## 프로젝트 구조

```
Freebuff_In_Termux/
├── src/
│   ├── index.ts                  # 공용 API 진입점
│   ├── types.ts                  # 공유 타입 정의
│   ├── utils/
│   │   ├── termux-utils.ts       # Termux 환경 감지
│   │   ├── path-utils.ts         # 경로 보정
│   │   └── system-utils.ts       # 시스템 정보 (arch, android ver, etc.)
│   └── proot/
│       ├── path-bridge.ts        # Termux ↔ proot 경로 변환
│       └── proot-wrapper.ts      # proot-distro 관리 클래스
├── tests/                        # Jest 테스트 (51개)
├── scripts/
│   └── install.sh                # Termux 설치 스크립트
└── docs/
    ├── PLAN.md                   # 다각도 개선 계획서
    ├── task_plan.md              # 진척 추적
    └── notes.md                  # 조사 결과
```

## API

### 유틸리티 함수

| 함수 | 설명 |
|------|------|
| `isTermux()` | Termux 환경 감지 |
| `getTermuxPrefix()` | Termux PREFIX 경로 반환 |
| `resolvePath(path)` | 절대 경로를 Termux PREFIX 기반으로 보정 |
| `getArch()` | CPU 아키텍처 반환 (aarch64, arm, x86_64) |
| `getAndroidVersion()` | Android 버전 조회 |
| `isProotAvailable()` | proot-distro 설치 여부 확인 |
| `normalizePathForTermux(path)` | 경로 정규화 (., .., ~, 중복 슬래시) |

### 경로 브리지

| 함수 | 설명 |
|------|------|
| `termuxToProot(path, config)` | Termux 경로 → proot 경로 |
| `prootToTermux(path, config)` | proot 경로 → Termux 경로 |
| `buildBindMountArgs(config)` | proot bind mount 인자 생성 |

### ProotDistroManager 클래스

```typescript
const mgr = new ProotDistroManager();
mgr.installDistro('ubuntu');        // distro 설치
mgr.installBunInDistro('ubuntu');   // Bun 설치
mgr.installFreeBuffInDistro('ubuntu'); // FreeBuff 설치
mgr.runFreeBuff('ubuntu', cwd, args);  // FreeBuff 실행
mgr.preflightCheck('ubuntu');       // 사전 검증
```

## 개발

```bash
# 의존성 설치
npm install

# 빌드
npm run build

# 테스트
npm test

# 커버리지
npm run test:coverage
```

## 에이전트/AI 통합 가이드

이 프로젝트는 **AI 코딩 에이전트**가 Termux 환경에서 FreeBuff를 활용할 수 있도록 설계되었습니다.

### 통합 가능한 에이전트 유형

| 에이전트 유형 | 통합 방식 | 사용 시점 |
|--------------|-----------|----------|
| **코딩 에이전트** | CLI 호출 (`freebuff --prompt "..."`) | 코드 생성/수정/분석 |
| **CLI 자동화 에이전트** | 스크립트 실행 | 빌드/배포 자동화 |
| **모니터링 에이전트** | 상태 확인 | 환경 건강 검사 |

### 에이전트가 알아야 할 핵심 사항

1. **도구 타입**: Bun 기반 CLI 도구의 Termux 호환 레이어
2. **호환 대상**: `freebuff` (Bun 컴파일 바이너리)
3. **실행 환경**: proot-distro Ubuntu 내부
4. **파일 접근**: 경로 자동 변환 (Termux ↔ proot)
5. **제약사항**: Bun이 Termux에서 직접 실행 불가 (이 레이어가 해결)

### 스킬 통합

[freebuff-hermes-integration](./skill/freebuff-hermes-integration/) 스킬을 통해 다른 에이전트와 연동 가능:

```typescript
import { ProotDistroManager, FreeBuffLauncher } from 'freebuff-termux';

// 1. 환경 검증
const mgr = new ProotDistroManager();
const check = mgr.preflightCheck('ubuntu');
if (!check.ready) throw new Error(check.missing.join(', '));

// 2. FreeBuff 실행
const launcher = new FreeBuffLauncher();
await launcher.launch('ubuntu', process.cwd(), []);
```

## 기술 제약

| 제약사항 | 설명 | 영향 |
|----------|------|------|
| Bun 컴파일 바이너리 | 소스 코드 비공개, 직접 수정 불가 | 이 호환 레이어 필요 |
| proot 오버HEAD | Linux 시뮬레이션으로 인한 성능 손실 | 미미 (일반적 사용에는 무시 가능) |
| OOM Killer | Android 메모리 부족 시 proot 프로세스 종료 | 대용량 작업 시 주의 |

## 라이선스

MIT
