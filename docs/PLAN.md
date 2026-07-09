# FreeBuff Termux 프로젝트 — 다각도 개선 계획서

## 1. 현황 분석

### 1.1. FreeBuff/CodeBuff 실체

| 항목 | Codebuff (유료) | FreeBuff (무료) |
|------|----------------|-----------------|
| npm 패키지 | `codebuff` v1.0.683 | `freebuff` v0.0.119 |
| 주간 다운로드 | 1,090 | 17,468 |
| 런타임 | Bun (shebang: `#!/usr/bin/env bun`) | 동일 (Codebuff 플랫폼 기반) |
| 빌드 방식 | `bun cli/scripts/build-binary.ts` 단일 바이너리 | `bun freebuff/cli/build.ts`가 `FREEBUFF_MODE=true`로 래핑 |
| 모델 | OpenRouter 전 모델 | DeepSeek, Kimi, MiniMax 등 오픈소스 |
| GitHub | `CodebuffAI/codebuff` (7.2k stars, 공개) | `CodebuffAI/freebuff-private` (비공개) |

### 1.2. 핵심 기술 제약
- FreeBuff는 **Bun 컴파일 바이너리**로 npm 배포
- Bun은 **Termux/Android aarch64에서 실행 불가** (GitHub Issue #5085, #28924)
- 소스 비공개 → 직접 수정 불가, 바이너리 래핑 또는 proot 환경 필요

### 1.3. 현재 프로젝트 문제점 (11건)

| # | 심각도 | 문제 |
|---|--------|------|
| 1 | 치명 | tsconfig.json 빌드 불가 (rootDir="./src"인데 src/ 없음) |
| 2 | 치명 | 실제 FreeBuff 변환 코드 부재 |
| 3 | 치명 | 설치 스크립트 부재 |
| 4 | 중요 | SKILL.md 잘못 배치 (→ FB-H-I/로 이동 완료) |
| 5 | 중요 | README 부재 |
| 6 | 중요 | 테스트 격리 결함 (env mutation 정리 없음) |
| 7 | 보통 | .skill 내 빈 리소스 디렉토리 |
| 8 | 보통 | 가상 명령어 참조 (hermes shell exec) |
| 9 | 보통 | 입력 검증 부재 (resolvePath 경계 케이스) |
| 10 | 보통 | 아키텍처 문서 부재 |
| 11 | 개선 | CI/CD 부재 |

## 2. 기술 전략: B+C 하이브리드

| 접근법 | 난이도 | 완성도 | 유지보수 | 설명 |
|--------|--------|--------|----------|------|
| A. 소스 빸드 변환 | 매우 높음 | 높음 | 어려움 | 7,310+ 커밋 전면 수정 (불가) |
| **B. proot-distro 래퍼** | 낮음 | 중간 | 쉬움 | Linux 환경 생성 후 Bun/FreeBuff 실행 |
| **C. Node.js 바이너리 교체** | 중간 | 중간 | 보통 | npm 패키지 바이너리 추출 후 Node.js 재실행 |

**채택: B + C 하이브리드** — proot-distro를 1차 메커니즘, 기존 유틸리티를 경로 브리지로 활용.

## 3. 7축 개선 계획

### 축 1: 프로젝트 구조 & 빌드 시스템 (Phase 1 — 현재 실행)
- `src/` 디렉토리 생성 및 .ts 파일 이동
- `tsconfig.json` 경로 수정
- `package.json` 스크립트 추가 (build, dev, start)
- `.gitignore` 생성
- 빌드 검증: `npx tsc` + `node dist/index.js`

### 축 2: 코드 품질 & 테스트 강화
- 테스트 격리 수정 (afterEach env 복원)
- 경계 케이스 테스트 추가 (빈 문자열, null, 상대경로, 틸다, Windows 경로)
- 입력 검증 추가
- 추가 유틸리티: getAndroidVersion, getArch, getStoragePath, isProotAvailable, normalizePathForTermux

### 축 3: FreeBuff Termux 실행 레이어
- proot-distro 래퍼 모듈 (ProotDistroManager 클래스)
- FreeBuff 바이너리 래퍼 (launcher)
- 설치 스크립트 (install.sh)
- 경로 매핑 레이어 (Termux ↔ proot 양방향 변환)

### 축 4: 스킬(.skill) 개선
- 루트 SKILL.md 교체/삭제 (→ FB-H-I/로 이동 완료)
- references/ 충실화 (CLI 옵션, proot 가이드, 트러블슈팅)
- scripts/ 충실화 (output parser, health check, launcher)
- templates/ 충실화 (wrapper, config 템플릿)
- 가상 명령어를 실제 실행 메커니즘으로 교체

### 축 5: 문서화 & 사용자 경험
- README.md, ARCHITECTURE.md, CONTRIBUTING.md, CHANGELOG.md
- 기존 TDD 문서 정리 (docs/ 이동, 인코딩 수정)
- docs/ 디렉토리 구조화

### 축 6: Termux 특화 기능
- 메모리 관리 (OOM Killer 대응)
- 배터리/절전 대응 (Doze 모드)
- 저장소 권한 (termux-setup-storage)
- 백그라운드 실행 (termux-wake-lock)
- Android 버전별 호환성 매트릭스

### 축 7: CI/CD & 품질 보증
- GitHub Actions (빌드, 테스트, 커버리지)
- ESLint + Prettier 설정
- husky + lint-staged (사전 커밋 훅)
- semver 버전 관리

## 4. 실행 순서

```
Phase 1: 기반 정비 (현재 실행 — 축 1 구조 구축까지만)
├── [1A] tsconfig.json 수정 + src/ 구조 생성
├── [1C] .gitignore 생성
└── 빌드 검증

Phase 2: 핵심 구현 (새 레포지터리에서 진행)
├── [2A] 추가 유틸리티 함수 구현
├── [2B] proot-distro 래퍼 모듈
├── [2C] 경로 브리지 모듈
└── [2D] 설치 스크립트

Phase 3: 통합 & 문서
├── [3A] FreeBuff 런처 구현
├── [3B] README + ARCHITECTURE
├── [3C] .skill 리소스 충실화
└── [3D] TDD 문서 정리

Phase 4: 품질 & 자동화
├── [4A] 경계 케이스 테스트
├── [4B] CI/CD 파이프라인
├── [4C] 린트/포맷팅
└── [4D] Termux 특화 기능
```

## 5. 가정 및 제약사항
1. proot-distro를 1차 전략으로 채택 (소스 변환은 비현실적)
2. Termux 실기기 검증은 사용자가 수행 (Windows 환경에서 작업)
3. FreeBuff 버전 독립적 설계 필요 (빠른 업데이트 중)
4. 네이티브 의존성(canvas 등) 포함 여부는 런타임 테스트로만 검증 가능
