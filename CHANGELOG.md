# Changelog

이 프로젝트의 주요 변경 사항은 이 파일에 기록됩니다.

형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 기반으로 하며,
이 프로젝트는 [Semantic Versioning](https://semver.org/lang/ko/)을 준수합니다.

## [Unreleased]

### Added
- README.md 에이전트/AI 통합 가이드 섹션 추가
  - 통합 가능한 에이전트 유형 테이블 (코딩, CLI 자동화, 모니터링)
  - 에이전트가 알아야 할 핵심 사항 5가지
  - 스킬 통합 코드 예시 (`freebuff-hermes-integration`)
- README.md 사전 요구사항 (Prerequisites) 섹션 추가
  - Termux, proot-distro, Node.js, Bun, storage 권한 요구사항 테이블
- FreeBuff 인터랙티브 런처 (`FreeBuffLauncher` 클래스)
  - `spawn` 기반 실시간 stdin/stdout/stderr 브리징
  - `Spawner` 인터페이스 주입으로 테스트 가능
  - 인터랙티브 모드 (`launch()`) 및 프로그래밍 모드 (`run()`)
  - SIGINT/SIGTERM 시그널 전달
- Termux 특화 기능 (`termux-features.ts`)
  - Wake Lock 관리 (`acquireWakeLock`, `releaseWakeLock`)
  - 저장소 권한 설정 (`setupStorage`, `isStorageSetup`)
  - 메모리 정보 조회 (`getMemoryInfo`)
  - OOM 위험도 평가 (`checkOomRisk`)
- `Spawner`, `SpawnResult`, `LaunchOptions`, `MemoryInfo`, `OomRiskAssessment` 타입
- Hermes Agent 연동 스킬 재작성 (실제 API 기반)
- CONTRIBUTING.md, ARCHITECTURE.md

## [0.0.2] - 2026-07-10

### Added
- 공유 타입 정의 (`types.ts`): `CommandRunner`, `ExecResult`, `ProotDistroConfig` 등
- 시스템 유틸리티 (`system-utils.ts`): `getArch`, `getAndroidVersion`, `isCommandAvailable`, `normalizePathForTermux`
- proot-distro 래퍼 (`proot-wrapper.ts`): `ProotDistroManager` 클래스
  - distro 설치/확인, Bun/FreeBuff 설치, FreeBuff 실행, 사전 검증
  - `CommandRunner` 인터페이스 주입으로 테스트 가능
- 경로 브리지 (`path-bridge.ts`): `termuxToProot`, `prootToTermux`, `buildBindMountArgs`
- Termux 설치 스크립트 (`scripts/install.sh`): 7단계 자동 설치
- README.md, docs/ARCHITECTURE.md, docs/PLAN.md, docs/notes.md, docs/task_plan.md
- 51개 테스트 (5 test suites)

### Changed
- README.md B+C 전략 설명 개선
  - 메타데이터 헤더 추가 (도구 타입, 대상, 전략)
  - B+C 전략 비교 테이블 + ASCII 아키텍처 다이어그램
  - 기술 제약사항을 테이블로 재구성
- 프로젝트 구조를 `src/` + `tests/` + `docs/` 분리 구조로 재편
- `tsconfig.json`에 `isolatedModules`, `declaration`, `sourceMap` 추가
- `package.json`에 `build`, `start`, `dev`, `test:coverage` 스크립트 추가
- `jest.config.cjs`로 전환 (ts-jest CommonJS 호환성)

### Fixed
- tsconfig.json `rootDir`/`include` 경로 불일치 해결
- `resolvePath` 이중 슬래시 버그 수정
- ESM 실행 가드 Windows 호환성 (`fileURLToPath`)
- `isCommandAvailable` 크로스 플랫폼 지원 (`where`/`command -v`)
- 테스트 환경 변수 격리 (`afterEach` 복원)

## [0.0.1] - 2026-07-10

### Added
- 초기 프로젝트 구조
- `termux-utils.ts`: Termux 환경 감지 (`isTermux`, `getTermuxPrefix`)
- `path-utils.ts`: 경로 보정 (`resolvePath`)
- 기본 테스트 (9개)
- LICENSE, .gitignore, .gitattributes
