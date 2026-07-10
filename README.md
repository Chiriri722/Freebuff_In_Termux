# FreeBuff in Termux

FreeBuff (무료 Codebuff)를 Android Termux 환경에서 실행하기 위한 호환 레이어입니다.

## 개요

[FreeBuff](https://www.npmjs.com/package/freebuff)는 터미널 기반 AI 코딩 에이전트로, [Codebuff](https://github.com/CodebuffAI/codebuff) 플랫폼 기반으로 구축되었습니다. 하지만 FreeBuff는 **Bun 런타임**으로 컴파일된 바이너리로 배포되며, Bun은 현재 **Termux/Android에서 실행할 수 없습니다** ([oven-sh/bun#5085](https://github.com/oven-sh/bun/issues/5085)).

이 프로젝트는 **B+C 하이브리드 전략**을 통해 이 문제를 해결합니다:

- **B (proot-distro)**: Termux 내부에 Linux 환경(Ubuntu)을 구성하여 Bun이 실행 가능한 환경을 제공
- **C (경로 브리지)**: Termux ↔ proot 간 파일 경로를 자동 변환하여 투명한 파일 접근 보장

## 빠른 시작

### Termux에서 설치

```bash
# 저장소 클론
git clone https://github.com/<your-username>/Freebuff_In_Termux.git
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

## 기술 제약

- FreeBuff는 Bun 컴파일 바이너리로 배포되므로 직접 소스 수정이 불가능합니다
- proot-distro 환경에서 실행 시 약간의 성능 오버헤드가 있습니다
- Android 기기의 메모리에 따라 proot 환경이 OOM Killer에 의해 종료될 수 있습니다

## 라이선스

MIT
