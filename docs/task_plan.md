# Task Plan: FreeBuff Termux — Phase 4 품질 & 자동화

## Goal
경계 케이스 테스트(4A), CI/CD 파이프라인(4B), 린트/포맷팅(4C), Android 호환성 문서(4D)를 완료한다.

## Phases
- [x] Phase 1: 프로젝트 구조 구축 (완료)
- [x] Phase 2: 핵심 구현 (51/51 passed)
- [x] Phase 3: 통합 & 문서 (67/67 passed)
- [x] Phase 4A: 경계 케이스 테스트 (edge-cases.test.ts — 30개 케이스)
- [x] Phase 4B: CI/CD 파이프라인 (GitHub Actions — Node 18/20/22 매트릭스)
- [x] Phase 4C: ESLint + Prettier 린트/포맷팅 (0 errors, all formatted)
- [x] Phase 4D: Android 버전별 호환성 매트릭스 문서
- [x] Phase 4-Verify: 빌드 + 테스트 + 린트 + 포맷팅 검증 (97/97 passed)

## Key Decisions
- ESLint flat config (eslint.config.js) 사용 — ESM 프로젝트 호환
- CI 매트릭스: Node.js 18, 20, 22 (Jest 30 호환 버전)
- 경계 케이스는 순수 함수에 집중 (Windows에서도 실행 가능)

## Errors Encountered
- [prettier 포맷팅 불일치] Prettier 적용 후 13개 파일 포맷팅 변경 → `prettier --write`로 일괄 수정
- [normalizePathForTermux trailing space] 테스트 예상값이 실제 동작과 불일치 → 세그먼트 내 공백은 보존됨(파일명에 공백 가능), 테스트 수정
- [ESLint prefer-const] system-utils.ts에서 `let normalized`가 재할당되지 않음 → `const`로 변경
- [ESLint 설치 불완전] npm install 타임아웃으로 eslint 바이너리 손상 → `npm install eslint@latest`로 재설치

## Status
**Phase 4 완료 — 품질 & 자동화 완료** — tsc 빌드 성공, 97/97 테스트 통과 (8 suites), ESLint 0 errors, Prettier all formatted

## Phase 5: 실기기 테스트 & URL 브리지 구현

### 진행 내역
- [x] 5-1: Termux SSH 원격 제어 환경 구축 (SSH 공개키 인증, IP 192.168.50.61:8022)
- [x] 5-2: proot-distro Ubuntu 컨테이너 충돌 진단 (`container already exists` → `--user root` 플래그로 해결)
- [x] 5-3: xdg-open 브리지 구현 — FreeBuff 로그인 URL을 Termux 브라우저로 전달
  - proot 내부 `/usr/local/bin/xdg-open` 스크립트가 URL을 `~/.freebuff-url-to-open`에 기록
  - 래퍼의 백그라운드 감시자(0.5초 간격)가 파일 감지 → `termux-open-url`로 브라우저 실행
- [x] 5-4: proot-distro v5.4.1 호환성 수정
  - **근본 원인**: `pkg upgrade`로 proot-distro가 v5.4.1로 업그레이드 → `/bin/bash -c` 실행 시 프로파일 스크립트가 PATH를 덮어쓰고 `declare -x` 환경 변수 출력 → `/usr/local/bin/` 내 파일(node, xdg-open) 인식 불가
  - **해결**: 모든 `bash -lc`/`bash -c` 호출을 `bash --norc --noprofile -c`로 변경
  - install.sh, remote-install.sh, freebuff-wrapper.sh — 총 14개 라인 수정
- [x] 5-5: 실기기 전체 플로우 검증 완료
  - `freebuff --version` → 0.0.122 ✅
  - xdg-open 브리지 → URL 파일 기록 ✅
  - 백그라운드 감시자 → `termux-open-url` 호출 → 브라우저 열기 ✅ (OPEN_EXIT=0)

### 발견된 단서
- FreeBuff 바이너리 내부에 `Bun.spawn(["xdg-open", url])` 코드 존재 — 로그인 시 xdg-open 호출
- Termux의 `xdg-open`은 `termux-open` → `am broadcast com.termux.app.TermuxOpenReceiver` → Android 브라우저 열기
- proot PATH에 `/data/data/com.termux/files/usr/bin` 포함 → Termux의 xdg-open이 fallback으로 작동 (이것이 이전에 크롬이 열린 원인)

### 남은 과제
- [ ] 5-6: 인 앱 메뉴 디렉토리 선택 → Enter → 인증 링크 플로우 사용성 개선 (가상 키보드 편법 없이 정상 작동)
- [ ] 5-7: GitHub 공개 후 fresh install 테스트 (다른 기기에서 `curl | bash` 원라인 설치)

## 전체 프로젝트 완료 요약
- Phase 1: 프로젝트 구조 구축
- Phase 2: 핵심 구현 (유틸리티, proot 래퍼, 경로 브리지, 설치 스크립트)
- Phase 3: 통합 & 문서 (런처, Termux 특화 기능, 스킬, 문서)
- Phase 4: 품질 & 자동화 (경계 케이스, CI/CD, 린트/포맷팅, 호환성 문서)
- 총 97개 테스트, 8 test suites, 0 lint errors
