# 2026-09-08 후속 수정 및 검증

기준 커밋 `979bb2b8230d68c68e86e7a69e6305c82b74ead1`의 F-033~F-041을 로컬 working
tree에서 수정했다. [원본 리뷰](./2026-09-08.md)는 수정 전 증거로 보존한다.

## 결과

| Finding | 수정                                               | 핵심 검증                                                                |
| ------- | -------------------------------------------------- | ------------------------------------------------------------------------ |
| F033    | 해시 확인 후 현재 Bash로 installer/bootstrap 실행  | 644 checkout·release artifact, repair/update, 변조 거부                  |
| F034    | 백그라운드 stdin 명시 redirection                  | pipe 및 Linux PTY FD 입력                                                |
| F035    | host HOME 소비 경로와 guest `/root` 쓰기 경로 분리 | 실제 PRoot HOME bind, 기록/0600, 동시 세션                               |
| F036    | 세 경로의 `cd` 실패 즉시 전파                      | 누락 CWD 차단 및 특수문자 argv                                           |
| F037    | 부모 close 뒤 group escalation 완료까지 대기       | timeout/abort/output-limit/host signals, 부모 선종료, zero grace         |
| F038    | EXIT cleanup까지 wrapper PGID 유지                 | 정상·비정상 종료 후 후손 sentinel 미생성                                 |
| F039    | 개별 validator 실패 명시 return                    | 완전한 manifest의 mutable image/unsafe identifier 거부                   |
| F040    | active pointer의 guest 대상과 실행 파일 확인       | 절대·상대 링크/npm symlink 정상, 누락·dangling·오버라이드·일반 파일 거부 |
| F041    | 출처 주석 허용과 변조 archive 회귀                 | SHA256/SHA512 실패 후 추출·실행·commit 미진입                            |

## 독립 검토

Codex Security fix-finding 절차로 수정 전 읽기 전용 경계 조사와 수정 후 별도 리뷰를
수행했다. 사후 리뷰는 부모 close 직후 호스트 SIGINT/SIGTERM handler를 제거해 grace
중 호스트가 종료될 수 있는 조건을 발견했다. 작성자가 새 테스트의 실패를 확인하고
handler 제거를 group 정리 완료 시점으로 옮겼다. 해당 테스트와 필수 게이트가 통과했다.
새 독립 리뷰가 이 후속 변경을 재승인했다고 주장하지 않는다.

## 게이트

- Linux Node 18.20.8, 20.20.2, 22.23.2: 각각 npm ci, build, Jest **17 suites / 185 tests**, skip 0.
- Linux Node 24.14.0: build/lint/format, Jest **185/185**, packed consumer 통과.
- Windows Node 24.14.0: build/lint/format, Jest **179 pass / 6 Linux-only skip**, 실패 0.
- Bats v1.14.0 **40/40**: 실제 PRoot 5.1.0 HOME bind, PTY stdin, bootstrap, doctor,
  프로세스 종료와 full installer SIGKILL/SIGTERM 복구 포함.
- production Bash 9개 개별 syntax, ShellCheck warning gate, shfmt 통과.
- 공식 archive checksum을 확인한 actionlint 1.7.12로 workflow 2개 통과.
- init reaper가 있는 Linux 컨테이너를 사용했다. init 없는 초기 fixture의 zombie PID
  실패는 실행 중 후손과 구분하고 정상 회수 환경에서 다시 검증했다.

## 개발 연동과 후속 작업

공식 Spec-kit v1.0.0 Codex 스킬 10개, constitution과
[spec/plan/tasks](../../specs/001-runtime-hardening/spec.md)를 추가했다. PowerShell
prerequisite checker가 활성 spec/tasks를 확인했다.
[Linear 프로젝트](https://linear.app/david-lee-722/project/freebuff-termux-d6b62b69085a)의
F033–F041 매핑은 [설정](../../config/development-integrations.json)에 있다.

Sentry `the-voltex-club/buff-termux` (`4512047923920976`)의 프로젝트/오류 읽기에
성공했다. 모든 환경, 최근 14일 미해결 오류는 0건(상한 20)이었다. SDK 수집 성공의
증거는 아니다. 토큰과 원본 이벤트는 문서/이슈에 저장하지 않았다.

실제 Android/Termux fresh/rerun, raw terminal/Ctrl-C 복구, 브라우저/clipboard,
storage와 lifecycle은 [기기 양식](../termux-evidence/TEMPLATE.md)으로 검증해야 한다.
새 GitHub checks와 Release는 실행하지 않았고 commit/push도 하지 않았다.

사용자 승인 후 Linear 수정 이슈 9건에 결과를 기록하고 Done으로 변경했다. 기기 검증은
[DAV-42](https://linear.app/david-lee-722/issue/DAV-42/t015-실제-androidtermux에서-런타임-수정-검증)에 Todo로 등록했다.
변경 문서의 상대 링크 57개, `git diff --check`, 공식 Codex 스킬 10개의 설치 hash도 확인했다.
