# Task Plan: FreeBuff Termux — Phase 2 핵심 구현

## Goal
B+C 하이브리드 전략의 핵심 로직을 구현한다: 추가 시스템 유틸리티(2A), proot-distro 래퍼(2B), 경로 브리지(2C), 설치 스크립트(2D).

## Phases
- [x] Phase 1: 프로젝트 구조 구축 (이전 세션 완료)
- [x] Phase 2A: 추가 유틸리티 함수 구현 (system-utils.ts)
- [x] Phase 2B: proot-distro 래퍼 모듈 (proot-wrapper.ts)
- [x] Phase 2C: 경로 브리지 모듈 (path-bridge.ts)
- [x] Phase 2D: 설치 스크립트 (install.sh)
- [x] Phase 2-Verify: 빌드 + 테스트 검증 (51/51 passed)

## Key Decisions
- CommandRunner 인터페이스 주입으로 proot-wrapper 테스트 가능성 확보
- 순수 함수(문자열 조작)는 path-bridge에, side-effect 함수는 system-utils에 분리
- install.sh는 Termux 전용 (shebang: #!/data/data/com.termux/files/usr/bin/bash)

## Errors Encountered
- [isCommandAvailable Windows 실패] `command -v`가 Windows에서 동작하지 않음 → `process.platform` 분기로 `where`/`command -v` 자동 선택하여 해결

## Status
**Phase 2 완료 — 핵심 구현 완료** — tsc 빌드 성공, 51/51 테스트 통과
