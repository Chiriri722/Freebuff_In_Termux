# Task Plan: FreeBuff Termux — Phase 3 통합 & 문서

## Goal
FreeBuff 인터랙티브 런처 구현(3A), 추가 문서(3B), Hermes Agent 스킬 재작성(3C), Termux 특화 기능(3D)을 완료한다.

## Phases
- [x] Phase 1: 프로젝트 구조 구축 (완료)
- [x] Phase 2: 핵심 구현 — 유틸리티, proot 래퍼, 경로 브리지, 설치 스크립트 (51/51 passed)
- [x] Phase 3A: FreeBuff 인터랙티브 런처 (freebuff-launcher.ts, spawn 기반)
- [x] Phase 3B: 추가 문서 (CONTRIBUTING.md, CHANGELOG.md)
- [x] Phase 3C: Hermes Agent 연동 스킬 재작성 (실제 API 기반)
- [x] Phase 3D: Termux 특화 기능 (termux-features.ts)
- [x] Phase 3-Verify: 빌드 + 테스트 검증 (67/67 passed, 7 suites)

## Key Decisions
- 런처는 Spawner 인터페이스 주입으로 테스트 가능 (execSync → spawn 전환)
- stdio: 'inherit' 모드로 인터랙티브 실행, 'pipe' 모드로 프로그래밍 실행 지원
- SIGINT/SIGTERM 시그널을 자식 프로세스에 전달하여 정상 종료 보장
- 스킬은 별도 skill/ 디렉토리에 배치, .skill 패키징 구조 유지

## Errors Encountered
(없음 — Phase 3에서 오류 없이 완료)

## Status
**Phase 3 완료 — 통합 & 문서 완료** — tsc 빌드 성공, 67/67 테스트 통과 (7 suites)
