# 내부 문서 안내

후속 작업은 [현재 작업 계획](../task-plan.md), [수정·검증 기록](./reviews/2026-09-08-hardening.md),
[개발 연동](./DEVELOPMENT_INTEGRATIONS.md)을 먼저 읽는다. 기준 리뷰는
`main@979bb2b8230d68c68e86e7a69e6305c82b74ead1`이며 F-033~F-041의 호스트 수정은 완료했다.
현재 실제 Termux 검증이 남아 있다.

## 목적에 따라 읽기

| 문서                                                                                 | 용도                               | 갱신 기준                             |
| ------------------------------------------------------------------------------------ | ---------------------------------- | ------------------------------------- |
| [README](../README.md)                                                               | 사용자 설치·실행·lifecycle 안내    | 사용자에게 보이는 동작이 바뀔 때      |
| [작업 계획](../task-plan.md)                                                         | 현재 우선순위와 완료 조건          | 다음 작업 또는 완료 상태가 바뀔 때    |
| [코드 리뷰](./reviews/2026-09-08.md)                                                 | F-033~F-041의 위치·재현·수정 방향  | 후속 수정 시 새 검증 결과를 연결      |
| [진행 기록](../progress.md)                                                          | 날짜별로 실제 실행한 검사와 제약   | 검증을 실행한 날                      |
| [조사 기록](../findings.md)                                                          | 기존 F-001~F-032의 발견·해결 이력  | 설계 근거나 발견 사항이 늘어날 때     |
| [아키텍처](./ARCHITECTURE.md)                                                        | 설치, 실행, 경로, URL, 복구의 책임 | 모듈 경계나 실행 계약이 바뀔 때       |
| [Android 호환성](./ANDROID_COMPATIBILITY.md)                                         | 실기기 지원 범위와 검증 매트릭스   | 실제 기기 evidence가 생길 때          |
| [기여 안내](../CONTRIBUTING.md)                                                      | 로컬 검증과 변경별 확인 절차       | 개발 도구나 게이트가 바뀔 때          |
| [Hermes API](../skill/freebuff-hermes-integration/references/freebuff_termux_api.md) | 공개 TypeScript API와 타입         | API를 변경할 때                       |
| [기기 evidence 양식](./termux-evidence/TEMPLATE.md)                                  | 릴리스에 사용할 실기기 검증 기록   | 검증이 끝나면 별도 evidence 파일 작성 |
| [CHANGELOG](../CHANGELOG.md)                                                         | 사용자에게 의미 있는 변경          | 동작 변경을 구현한 뒤                 |

## 과거 기록 읽기

[초기 계획](./PLAN.md), [이전 단계 기록](./task_plan.md), [초기 조사](./notes.md)는 역사 자료다. 당시 버전, 완료 표시, 외부 서비스 수치가 현재에도 유효하다는 뜻은 아니다. 기존 링크를 보존하기 위해 파일을 이동하지 않는다.

루트 `findings.md`와 `progress.md`의 2026-08-23 기록도 당시 증거다. 최신 요약은 각 문서 상단에 두고 이전 기록을 덮어쓰지 않는다. 구현 완료, 호스트 검증, 실제 Termux 검증, GitHub 실행 결과를 서로 구분한다.

## 코드와 테스트를 함께 읽기

| 경계             | 구현                                                              | 확인할 테스트                                                        |
| ---------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------- |
| 설치·복구        | `scripts/install.sh`, `scripts/lib/install-transaction.sh`        | `tests/shell/installer-integration.bats`, `install-transaction.bats` |
| 실행·종료·로그인 | `scripts/freebuff-wrapper.sh`, `scripts/xdg-open-bridge.sh`       | `tests/shell/wrapper.bats`, `url-bridge.bats`                        |
| 진단·lifecycle   | `scripts/manage.sh`                                               | `tests/lifecycle.test.ts`, `tests/shell/manage.bats`                 |
| TypeScript 실행  | `src/proot/freebuff-launcher.ts`, `proot-wrapper.ts`              | launcher/manager, spawner, Linux process 테스트                      |
| 경로·환경        | `src/proot/path-bridge.ts`, `src/utils/`                          | path/system/termux/edge-case 테스트                                  |
| 배포             | `scripts/remote-install.sh`, `release-*.sh`, `.github/workflows/` | release/package 계약, packed consumer, release Bats                  |

코드 탐색은 지식 그래프를 우선 사용한다. 그래프가 없으면 인덱스를 만들고, 제외된 shell/config 파일과 불충분한 결과는 직접 읽는다. 자동 생성되는 `.codebase-memory` 변경을 기능 변경으로 섞지 않는다.
