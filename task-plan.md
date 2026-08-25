---
plan_id: freebuff-termux-hardening-v1
status: host-and-linux-implementation-complete-termux-and-github-validation-pending
current_phase: 'Phase 5 — 테스트 계층·실제 Termux 검증·CI'
next_step: 'aarch64 Termux evidence를 수집한 뒤 변경을 push해 새 GitHub required checks를 실행한다.'
repository: 'Chiriri722/Freebuff_In_Termux'
baseline_branch: 'main'
baseline_commit: '4c6e746fa7e1d9892383403ce47c2ae2211a4a2d'
baseline_commit_date: '2026-07-23'
created_at: '2026-08-15'
last_updated: '2026-08-23'
target_path: 'task-plan.md'
implementation_started: true
review_method: '기존 ChatGPT Pro 산출물 복원 + 로컬 지식 그래프 + 공식 upstream 계약 + 전체 호스트 게이트'
companion_files:
  - findings.md
  - progress.md
legacy_documents:
  - docs/PLAN.md
  - docs/task_plan.md
  - docs/notes.md
---

# Task Plan: FreeBuff in Termux — 안전성·재현성·실기기 품질 강화

## Goal

현재 동작하는 FreeBuff–Termux 호환 레이어를 입력 안전성, 실패 복구, 실기기 검증, 버전 고정, 릴리스 추적이 가능한 유지보수형 도구로 발전시킨다.

## 운영 규칙

- `[ ]` 시작 전, `[-]` 진행 중, `[x]` 구현과 검증 완료, `[!]` 차단됨.
- Phase는 Exit Gate와 `progress.md` 증거까지 갖춰야 완료한다.
- 정적 분석, 호스트 테스트, Linux 통합 테스트, 실제 Termux 테스트를 별도 증거 등급으로 기록한다.
- 새 설계 선택과 실패한 명령은 각각 Decision Log와 Errors Encountered에 남긴다.
- 프로세스 수명, 설치 복구, 사용자 데이터 보존, 인증 URL 보호를 새 기능보다 우선한다.
- 사용자 입력이 셸 명령 문자열에 직접 삽입되는 변경은 병합하지 않는다.

## 제품 불변 조건

- 사용자 프로젝트, Git 상태, 인증 정보, 기존 설정을 자동 삭제하거나 덮어쓰지 않는다.
- 설치기는 전체 Termux 환경을 암묵적으로 `pkg upgrade`하지 않는다.
- distro, user, path, mount, CLI 인자는 argv 또는 위치 인자로 전달한다.
- 로그인 URL은 http/https만 허용하고 길이·개행·제어문자를 검증한다.
- 인증 상태는 세션별 0700 디렉터리와 0600 파일 또는 동등한 수단으로 보호한다.
- `/storage/emulated/0` bind는 기본 요구사항이 아니다.
- 정상 종료, Ctrl-C, SIGTERM, timeout 뒤 프로젝트 소유 자식 프로세스가 남지 않는다.
- 메모리·환경 정보 조회 실패를 `safe`로 간주하지 않는다.
- 네트워크 산출물은 버전과 무결성을 검증한다.
- 재설치는 멱등이어야 하고, 실패한 설치는 가능한 범위에서 롤백한다.
- 호스트 CI 성공을 Android/Termux 실기기 성공으로 표현하지 않는다.

## 기준선

| 항목                     | 상태                                             |
| ------------------------ | ------------------------------------------------ |
| Git                      | `main@4c6e746fa7e1d9892383403ce47c2ae2211a4a2d`  |
| 호스트 build/lint/format | 2026-08-23 통과                                  |
| Windows tests            | 16 suites, Linux-only 3 skip                      |
| Linux Node 22 tests      | 16 suites/175 pass, skip 0                        |
| Linux shell/package      | Bats 26/26 pass (full installer 포함), pack 55    |
| 실제 Termux              | 기존 문서에 일부 성공 이력, 독립 재현 필요       |
| 태그/Release             | 없음                                             |
| 브랜치 보호              | 없음(원격 후속 작업)                             |

## Findings 우선순위

### P0 — 공개 설치 전 해결

- [-] F-001: `set -e` 아래 watcher의 `((count++))` 조기 종료 — 호스트 수정·계약 테스트 완료, Termux 증거 대기.
- [-] F-002: `exec proot-distro`가 EXIT cleanup을 우회해 watcher가 남을 수 있음 — supervisor 구현·계약 테스트 완료, Termux signal 증거 대기.
- [-] F-003: 고정 `~/.freebuff-url-to-open` 파일의 동시 세션 충돌·URL 노출 — 세션별 private bridge·URL 정책·원자적 consume 구현, Termux 동시 세션 증거 대기.
- [x] F-004: distro/user/bind/path/command 셸 문자열 보간 — TS 동기·비동기 실행을 구조적 argv와 식별자 검증으로 전환.
- [x] F-005: TypeScript `bash -lc`와 실기기 `--norc --noprofile -c` 드리프트 — wrapper·launcher·manager·health check 계약 통일.
- [-] F-006: `health_check.sh`의 산술 증가 조기 종료, `eval`, 구형 shell 계약 — argv probe와 `--norc --noprofile`로 수정, Termux 증거 대기.
- [x] F-007: 설치기의 검증되지 않은 distro 기반 경로 계산·파일 쓰기 — 셸 identifier 검증을 경로 계산 전에 적용.
- [-] F-008: mutable `main` 기반 원라인 설치와 미검증 의존성 다운로드 — full SHA 또는 tag+expected commit bootstrap, pinned Node/FreeBuff 구현; Release artifact 증거 대기.

### P1 — 안정 릴리스 전 해결

- [x] F-009: ARM64 고정 Node tarball과 체크섬 부재 — dpkg arch 매핑과 공식 arm64/x64 archive SHA-256 고정.
- [x] F-010: 전체 `pkg upgrade`와 숨겨진 오류 — 제거하고 dpkg repair 실패를 명시적으로 중단.
- [x] F-011: wrapper/bridge가 여러 heredoc에 중복됨 — canonical 파일 원자 설치로 단일화.
- [x] F-012: storage bind 기본 활성·중복 가능성 — 기본 off, 명시적 opt-in, 중복 제거.
- [x] F-013: PREFIX/HOME 혼동에 따른 rootfs 경로 오류 — PREFIX 기본값과 distro 검증 통일.
- [x] F-014: `/proc/meminfo` 실패를 safe로 판정 — `unknown` 등급 도입.
- [x] F-015: 강제되지 않는 preflight, 무제한 pipe, 불완전 timeout cleanup — preflight 강제, 합산 출력 예산, AbortSignal, TERM→KILL, process-group cleanup 구현.
- [x] F-016: 임의 절대 경로에 PREFIX를 붙이는 `resolvePath()` — 알려진 Termux system root만 변환하도록 수정.
- [x] F-017: 현재 결함을 기대값으로 고정한 테스트 — path/storage/OOM 기존 기대를 안전 계약으로 교체.
- [-] F-018: ShellCheck/Bats/installer/PRoot/Termux 게이트 부재 — Linux Jest/Bats/full-installer gate 구현·로컬 실행 완료, 실제 PRoot·Termux와 새 GitHub run 대기.
- [x] F-019: npm 배포 계약 불명확 — ESM exports/types/files allowlist·prepack·Node engine·metadata와 pack 계약 테스트 구현.
- [x] F-020: README·계획·호환성 문서 드리프트 — 문서 smoke 계약과 README/Hermes/API 동기화.
- [-] F-021: PRoot-Distro v5 계약 드리프트 — `list --quiet`, `--isolated --shared-home`, digest-pinned OCI 설치로 수정; 실제 기기 증거 대기.
- [x] F-022: 잔여 host shell probe — `execSync`와 HOME 문자열 실행을 `execFileSync`·PATH/파일시스템 API로 제거.
- [x] F-023: installer가 기존 사용자 파일과 전역 `/usr/local/bin`을 소유한다고 가정 — manifest path/hash 경계 검증, 기존 distro 명시적 adoption, 프로젝트 전용 `/opt/freebuff-termux/current-*` runtime으로 전환.
- [x] F-024: FreeBuff npm tarball 무결성 미검증 — 0.0.152 SHA-512 고정 및 custom version 필수 checksum 검증.
- [x] F-025: 여러 managed file 사이 hard-exit crash consistency 부재 — context-bound transaction journal, 전체 old-set recovery, failpoint Bats 구현.
- [x] F-026: source tree 테스트만 있고 실제 npm 소비자 경계 부재 — exact 55-entry allowlist, 실제 pack·빈 프로젝트 설치·공개 API/CLI smoke 구현.
- [x] F-027: evidence 파일이 자기 자신을 포함하는 tag commit SHA를 요구하는 불가능한 release gate — tested runtime commit + evidence-only tag commit ancestry/exact-diff preflight로 교체.
- [x] F-028: 실제 Linux child/grandchild process-group 및 aggregate output/timeout/abort 동적 증거 부족 — Podman WSL2 Linux에서 Jest 3건과 `setsid` child/grandchild Bats 통과.
- [x] F-029: 기본 Node checksum을 archive와 같은 origin의 live `SHASUMS256.txt`에만 의존 — 공식 v22.17.1 arm64/x64 SHA-256을 installer에 고정하고 custom version은 명시 checksum을 강제.
- [x] F-030: 실행 파일만 있으면 manifest가 소유하지 않는 사전 배치 runtime root를 신뢰 — exact installer marker 또는 현 manifest ownership 없이는 실행 전 거부.
- [x] F-031: URL bridge의 shell glob이 `/`까지 매칭해 session 경로 traversal을 허용 — 정확한 6자리 session suffix 정규식으로 fail-closed 전환.
- [x] F-032: custom runtime checksum이 manifest/repair에서 소실되고 packed consumer가 lifecycle asset을 실행하지 않음 — checksum 보존·전달과 packed `doctor --json` smoke 추가.

## Phase Plan

- [x] Phase 0 — 계획 채택 및 호스트 기준선 재현
  - Exit: 루트 계획/findings/progress 생성, 깨끗한 호스트 build/test/lint/format 증거 기록.
- [-] Phase 1 — wrapper·URL bridge·프로세스 수명 P0 수정
  - supervisor가 child PID와 exit code를 소유하고 signal/cleanup을 보장한다.
  - watcher 산술 증가를 `set -e` 안전 형태로 교체한다.
  - 세션별 URL 상태, `umask 077`, URL 정책, 원자적 consume를 도입한다.
  - xdg shim과 health check를 새 계약에 맞춘다.
  - Exit: 정상/오류/Ctrl-C 뒤 잔존 프로세스 0, 두 세션 교차 전달 0, invalid URL 전달 0.
- [x] Phase 2 — TypeScript 실행 계약과 경로·입력 안전성 통합
  - 단일 `CommandSpec(command, args[])`, 식별자 검증, `--norc --noprofile`, process-group cleanup.
  - Exit: 셸/TypeScript 골든 계약과 injection 회귀 테스트 통과.
- [-] Phase 3 — 재현 가능한 install/update/repair/uninstall
  - canonical template, 원자적 설치, manifest, rollback, 의존성 pin·checksum.
  - Exit: fresh/rerun/failure injection/update/rollback/uninstall 통합 테스트 통과.
- [x] Phase 4 — config·doctor JSON·Hermes 계약
  - schema 검증, 구조화 진단·종료 코드, Hermes의 사람용 출력 파싱 제거.
  - Exit: `doctor --json` 계약 테스트와 민감 정보 redaction 통과.
- [-] Phase 5 — 테스트 계층·실제 Termux 검증·CI
  - ShellCheck/shfmt/Bats, Linux PRoot fixture, Termux 증거 매트릭스, required checks.
  - Exit: P0 검증 100%, 모든 지원 조합에 최근 evidence.
- [-] Phase 6 — 패키징·버전·릴리스 공급망
  - package/CLI/tag/CHANGELOG 정합, Release artifact/checksum/manifest/rollback.
  - Exit: 첫 태그와 Release, 깨끗한 Termux 설치, rollback 검증.
- [-] Phase 7 — 문서·호환성·사용자 UX
  - evidence 등급 지원표, 안전 설치/update/repair/uninstall, Phase 5-7~5-9 UX 과제.
  - Exit: 문서 명령 smoke test 100%, 모든 지원 표시에 evidence.

## 원자 PR 순서

| PR    | 범위                                       | 병합 조건                     |
| ----- | ------------------------------------------ | ----------------------------- |
| PR-00 | 루트 계획, findings/progress, 기준선       | 문서와 기준선 증거            |
| PR-01 | wrapper lifecycle + health check 긴급 수정 | signal/cleanup 셸 계약 테스트 |
| PR-02 | 세션별 URL bridge + xdg shim               | 동시성·URL policy 테스트      |
| PR-03 | CommandSpec + 입력 검증 + `--norc` 통합    | injection/argv 골든 테스트    |
| PR-04 | path/storage bind/OOM unknown              | path/config 계약 테스트       |
| PR-05 | installer 공통 코어 + 원자적 설치          | 실패 주입·rollback 테스트     |
| PR-06 | update/repair/uninstall/doctor JSON        | lifecycle 통합 테스트         |
| PR-07 | shell/CI/branch protection                 | required checks green         |
| PR-08 | Hermes/README/호환성 문서                  | 문서 명령 smoke test          |
| PR-09 | 버전 정합 + release workflow               | RC 실기기 gate                |
| PR-10 | 첫 stable Release                          | 전체 Definition of Done       |

## P0 검증 추적

- [-] V-001 정상 종료: host Bats에서 exit code·session cleanup 통과, 실제 PRoot 잔존 PID 대기.
- [-] V-002 Ctrl-C: Linux `setsid` TERM→KILL과 잔존 child/grandchild 0 통과, 실제 Termux terminal/PRoot 대기.
- [-] V-003 timeout: Linux Node process-group TERM→KILL과 잔존 grandchild 0 통과, 실제 PRoot tree 대기.
- [x] V-004/V-005 경로: 공백·한글·quote·`$()`·`;`·backtick을 문자 그대로 보존.
- [x] V-006 인자: leading dash·개행·unicode argv 경계 보존.
- [x] V-007/V-008 악성 distro·user를 실행 전 거부.
- [x] V-009/V-010 storage bind dedupe 및 home-only 동작.
- [x] V-011 존재하지 않는 custom mount의 구조화 오류.
- [-] V-012 정상 HTTPS URL을 1회 전달 후 삭제 — host Bats 통과, Android intent 대기.
- [x] V-013 위험 스킴·개행·초과 길이를 거부.
- [-] V-014 동시 세션 교차 전달·삭제 0 — session 격리 계약 구현, 실기기 동시 실행 대기.
- [-] V-015/V-016 browser/clipboard/수동 fallback capability 판정 — host fallback 계약 통과, Android capability 대기.
- [-] V-017~V-026 install/update/rollback/uninstall에서 무결성·사용자 파일 보존 — Linux 실제 installer hard-crash recovery 통과, Termux fresh/lifecycle 대기.
- [x] V-027 meminfo 없음은 unknown.
- [x] V-028 storage disabled는 전체 fail이 아님.
- [x] V-029 stale `bash -lc` PATH 문제에 remediation 제공.
- [x] V-030 큰 출력에 예산 적용.
- [x] V-031 AbortSignal의 구조화 abort·cleanup과 spawn-race 방어.
- [x] V-032 npm pack 계약.
- [-] V-033 Release artifact checksum — Linux에서 full 67-entry artifact·8 script checksum·최종 SHA 검증 통과, 실제 GitHub Release 대기.
- [x] V-034 Hermes `doctor --json` fail 시 실행 중단.
- [x] V-035 Hermes 변경 뒤 diff·test 검토.
- [x] V-036 악성 manifest가 사용자 파일을 가리켜도 doctor/uninstall이 mutation 전에 거부.
- [x] V-037 hard exit 뒤 다음 실행이 managed old-set 전체를 복원하고 stale transaction을 정리.
- [x] V-038 실제 npm tarball을 빈 소비자에 설치하고 allowlist·공개 API·CLI를 검증.
- [x] V-039 release preflight가 tested/tag ancestry와 evidence-only diff를 강제하고 최종 tar bytes 변조를 거부.
- [x] V-040 Linux 실제 stdout/stderr aggregate limit, timeout/abort, TERM→KILL, grandchild 잔존 0 — Node 22.17.1 Debian/WSL2에서 동적 통과.
- [x] V-041 기본 Node arm64/x64 digest 고정, custom Node/FreeBuff checksum manifest 보존과 repair 전달.
- [x] V-042 unowned/unmarked runtime root 거부와 verified interrupted-runtime 재사용.
- [x] V-043 transaction 5개 중단 지점 각각의 SIGKILL next-run recovery와 SIGTERM 즉시 rollback.
- [x] V-044 두 concurrent wrapper의 URL 교차 전달 0과 bridge session-path traversal 거부.

## Decision Log

- D-001: 루트 `task-plan.md`를 후속 단일 기준으로 사용하고 `docs/task_plan.md`는 역사 문서로 보존한다.
- D-002: 새 기능보다 P0 프로세스 수명·입력 안전성·URL 격리를 우선한다.
- D-003: 실행 명령은 `CommandSpec(command, args[])` 단일 원본을 목표로 한다.
- D-004: 안정 설치는 tag/Release artifact에 고정한다.
- D-005: storage bind는 기본 비활성으로 전환한다.
- D-006: 구현 변경은 RED→GREEN→REFACTOR TDD로 진행한다.
- D-007: PRoot-Distro v5 runtime은 `--isolated --shared-home`을 사용해 HOME만 공유하고 기본 Android storage bind를 차단한다.
- D-008: PRoot rootfs는 SHA-256 digest가 고정된 OCI image만 설치하고 GitHub Actions도 commit SHA로 고정한다.
- D-009: install manifest schema 2는 `proot_image`를 필수로 하며 JSON doctor 오류는 stderr 없이 단일 redacted 객체로 반환한다.
- D-010: host probe도 셸 문자열 실행을 허용하지 않고 argv 또는 파일시스템 API를 사용한다.
- D-011: Node/FreeBuff 실행 포인터는 `/usr/local/bin`이 아니라 `/opt/freebuff-termux/current-*` 프로젝트 전용 경계 안에서만 관리한다.
- D-012: installer의 다중 파일 교체는 context-bound transaction journal을 먼저 내구화하고 manifest를 마지막에 commit한다.
- D-013: release tag는 실기기 tested commit의 evidence-only 자손에 두고, preflight가 유일 변경 경로를 증명한다.
- D-014: npm publish payload는 개수만 보지 않고 exact allowlist와 clean-consumer install로 검증한다.
- D-015: Windows skip을 완료 증거로 취급하지 않고 pinned Node 22.17.1 Debian 컨테이너에서 lockfile 재설치 후 Linux 동적 계약을 실행한다.

## Errors Encountered

- E-001: 기존 Pro 계획 파일은 로컬 저장소에 없었음. 2026-08-23 agbrowse로 같은 ChatGPT 대화의 Library artifact를 복원했다.
- E-002: `agbrowse web-ai send`가 열린 Chat 대화를 Work surface로 오판했다. 표준 snapshot/ref 입력으로 후속 질문 전송에 성공했다.
- E-003: `agbrowse web-ai render` 종료 시 Windows libuv assertion이 발생했다. 렌더 결과 자체는 확인했고 live send에는 사용하지 않았다.
- E-004: 샌드박스에서 Jest worker와 `execSync('where node')`가 EPERM으로 실패했다. `--runInBand`와 승인된 샌드박스 밖 재실행으로 97/97 통과를 확인했다.
- E-005: 실제 Termux/Android 환경은 현재 세션에 없다. 실기기 Exit Gate는 로컬 호스트 결과로 대체하지 않는다.
- E-006: Windows 기본 `bash.exe`는 WSL 서비스 E_ACCESSDENIED, Git Bash는 샌드박스 signal pipe 오류가 발생했다. 승인된 Git Bash `bash -n`으로 5개 셸 파일 문법 검사를 통과했다.
- E-007: 기본 npm cache로 `npm pack --dry-run` 실행 시 EPERM이 발생했다. 임시 cache로 재실행해 52-entry payload를 검증했다.
- E-008: npm의 `@bats-core/bats@1.14.0`은 404, `bats@1.14.0`은 ETARGET이었다. npm에 게시된 `bats@1.13.0`으로 8개를 통과했고 Git Bash에 없는 setsid 동적 1개는 Linux CI로 이관했다.
- E-009: shfmt 첫 실행에 잘못된 health-check 경로를 넘겨 실패했다. 실제 canonical 경로로 정정해 6개 파일 포맷·diff 검사를 통과했다.
- E-010: 이 호스트에는 Docker CLI가 없어 별도 Linux container 실행 증거를 추가할 수 없었다.
- E-011: 첫 signal Bats stub의 외부 `sleep` 손자가 Windows PTY를 붙잡았다. 해당 테스트가 만든 PID와 임시 디렉터리만 확인해 제거하고 외부 자식 없는 stub으로 교체했다.
- E-012: Git Bash에는 `setsid`가 없어 process-group 동적 Bats 1개를 skip했다. CI는 Ubuntu `util-linux`를 명시 설치해 이 케이스를 실행한다.
- E-013: agbrowse의 광범위한 저장소 업로드는 안전 경계에서 차단됐다. 민감 내용을 제외한 구현·검증 요약만 기존 Pro 대화에 전송해 H-01~H-06 권고를 회수했다.
- E-014: agbrowse watcher는 응답 대기 중 timeout이 났지만 같은 session의 `sessions show`로 완성된 Pro 응답을 복구했다.
- E-015: 실제 npm 소비자 smoke는 샌드박스 child spawn EPERM이 발생했고 Windows `npm.cmd` 직접 spawn은 EINVAL이었다. `process.execPath`+`npm_execpath`로 교정하고 승인된 샌드박스 밖에서 통과했다.
- E-016: scoped npm Bats package 조회는 404였다. 공식 `bats-core` v1.14.0 tag를 임시 도구 디렉터리에 shallow clone해 전체 19건을 실행했다.
- E-017: WSL CLI 열거는 E_ACCESSDENIED였으나 실행 중인 Podman WSL2 machine을 발견해 실제 Linux 증거 경로로 전환했다.
- E-018: Windows에서 설치한 `unrs-resolver` native binding 때문에 bind-mounted Jest가 transformer를 찾지 못했다. Linux overlay에서 `npm ci`로 lockfile 의존성을 새로 설치해 해결했다.
- E-019: 실제 Linux Bats가 PGID 게시 직후 도착한 TERM 경합에서 wrapper 무한 대기를 재현했다. early-signal 분기도 bounded `stop_freebuff_group`을 호출하도록 RED→GREEN 수정했다.
- E-020: `runFreeBuff` argv 테스트가 Linux의 `HOME=/root`에 영향을 받아 실패했다. 테스트가 의도한 Termux/PRoot home을 명시해 플랫폼 우연성을 제거했다.
- E-021: 첫 slim-container 전체 Bats는 `git` 부재로 release fixture 7건이 setup 실패했다. ephemeral 컨테이너에 git을 설치한 뒤 20/20을 통과했다.
- E-022: 첫 local release 조립 명령에서 중첩 awk `$1` quoting이 `set -u`에 걸렸다. `cut` 기반 digest 추출로 교정해 full artifact 검증을 통과했다.
- E-023: GitHub API는 샌드박스 proxy에서 차단됐고 승인된 읽기 전용 재실행으로 원격 상태를 확인했다.
- E-024: Windows 기본 npm cache를 쓴 최종 `npm pack --dry-run`은 cache tmp 파일 EPERM으로 실패했다. 읽기 전용 Linux overlay에서 lockfile install 후 재실행했다.
- E-025: 문서 일부 범위를 한 번에 읽는 PowerShell 진단식은 중첩 배열 형식 오류로 중단됐다. 파일별 단순 범위 읽기로 교정했다.
- E-026: 첫 Linux pack 결과 파서는 중첩 shell/Node 인용에서 따옴표가 소실됐다. JSON의 `path` 항목을 직접 계수해 exact 55 entries를 재확인했다.
- E-027: 호스트에 ADB, Android SDK, emulator가 없고 연결 기기도 없어 실제 Termux 실행 경로를 만들 수 없었다. 실기기 gate는 계속 분리했다.
- E-028: agbrowse session 목록은 sandbox 밖 session lock 파일 접근이 EPERM이었다. 승인된 읽기 전용 재실행으로 기존 FreeBuff Pro session을 식별했다.
- E-029: 현재 미공개 구현·보안 결과를 Pro 대화로 재전송하는 요청은 외부 반출 안전 검토에서 거절됐다. 우회하지 않고 이미 회수한 H-01~H-06 기준으로 로컬 재감사를 진행했다.
- E-030: Windows PowerShell에서 `tests/*.test.ts` glob을 rg positional path로 넘겨 OS error 123이 발생했다. `-g '*.test.ts'` filter로 교정했다.
- E-031: 첫 targeted Jest 명령은 npm 인자 전달 방식 때문에 `--runInBand`가 npm option으로 해석되고 worker EPERM이 발생했다. Jest CLI를 Node로 직접 실행해 의도한 RED를 확인했다.
- E-032: URL bridge 테스트 파일명을 `bridge.bats`로 잘못 조회했다. `rg --files tests/shell`로 실제 `url-bridge.bats`를 확인했다.
- E-033: 임시 도구 검색 중 다른 프로세스 소유 temp 디렉터리 일부가 access denied를 반환했다. 검색 결과에서 전용 `freebuff-static-tools-20260823` 경로만 사용했다.
- E-034: shfmt를 CI 범위 밖의 기존 Bats 2-space 파일까지 확장해 diff가 발생했다. production 9개 파일은 clean이었고 Bats는 기존 파일별 스타일을 보존했다.
- E-035: Windows coverage의 npm/Git Bash child spawn이 sandbox EPERM으로 실패했다. 동일 명령을 승인된 sandbox 밖에서 재실행해 172 pass/3 Linux-only skip을 확인했다.
- E-036: 첫 final artifact command를 JavaScript template literal에 직접 넣어 shell `${...}`가 JS interpolation으로 해석됐다. shell statement 배열을 조합하는 방식으로 교정해 67-entry artifact를 검증했다.

## Immediate Next Actions

1. aarch64 Termux에서 fresh/rerun, normal/Ctrl-C/timeout process tree, URL bridge, checksum failure, lifecycle evidence를 수집한다.
2. 변경을 검토·커밋·push한 뒤 새 CI의 Node 18/20/22, Linux Bats, root installer recovery 결과를 기록한다.
3. 성공한 check 이름으로 main branch protection과 required checks를 적용한다.
4. 가능하면 x86_64 Android emulator에서도 같은 최소 매트릭스를 실행한다.
5. tested runtime 뒤 evidence 파일만 추가한 커밋에 tag를 두고 preflight가 ancestry와 exact diff를 통과할 때만 PR-10 stable Release를 진행한다.

## Definition of Done

- 모든 P0와 합의된 P1 항목이 완료되고 각 Phase Exit Gate에 증거가 있다.
- 명령 주입 가능 경로 0, 종료 유형별 잔존 프로젝트 프로세스 0, 세션 종료 후 URL 상태 파일 0.
- 검증된 Release artifact가 실제 깨끗한 Termux에서 설치·실행·로그인·종료·제거된다.
- 악성 입력, 부분 실패, checksum mismatch, 동시 세션, signal/timeout 테스트가 통과한다.
- 사용자 프로젝트·인증·비프로젝트 파일이 보존된다.
- package/CLI/tag/CHANGELOG와 README/Hermes/API가 동일한 버전·계약·지원 범위를 말한다.
- `findings.md`, `progress.md`, Decision Log, Errors Encountered와 Release notes가 최종 상태다.
