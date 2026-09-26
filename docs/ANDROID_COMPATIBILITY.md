# Android·Termux 호환성 및 evidence

## 현재 결론

2026-09-08 리뷰의 호스트 결함 9건을 수정했다. Linux Node 18/20/22/24에서 Jest 185/185,
Bats 40/40과 필수 호스트 게이트가 통과했다. 실제 Linux PRoot HOME bind와 PTY 입력도
확인했다. [수정 기록](./reviews/2026-09-08-hardening.md)을 기준으로 실제 Termux 검증을 진행한다.

2026-08-23에는 Node 22.17.1 Debian/WSL2 Linux 검증 기록이 있지만 독립된 실제 Termux 기기 evidence는 아직 수집되지 않았다. 특정 Android 버전을 “완전 호환”으로 표시하지 않는다. 첫 stable Release는 실제 기기에서 검증한 runtime commit과 그 직후의 evidence-only tag commit이 없으면 생성되지 않도록 차단돼 있다.

## 의도한 지원 범위

| 항목         | 의도한 범위                                                                                      | 현재 증거                             |
| ------------ | ------------------------------------------------------------------------------------------------ | ------------------------------------- |
| Termux       | F-Droid 또는 공식 GitHub 배포판의 최신 계열                                                      | 실제 기기 재검증 대기                 |
| PRoot-Distro | [v5 계약](https://github.com/termux/proot-distro)(`list --quiet`, `--isolated`, `--shared-home`) | 정적·호스트 계약 통과                 |
| Android CPU  | aarch64/arm64, x86_64/amd64                                                                      | installer 매핑 테스트 통과, 기기 대기 |
| Android 버전 | 최소 버전 미확정                                                                                 | 기기 매트릭스 필요                    |
| Linux rootfs | digest-pinned Ubuntu 24.04, Debian 12-slim                                                       | installer 계약 통과, 설치 대기        |
| Runtime      | pinned Node.js + pinned FreeBuff                                                                 | checksum/버전 계약 통과, 실행 대기    |

ARM32와 i386은 TypeScript의 환경 감지 값에는 존재하지만 canonical installer가 해당 Node archive를 지원하지 않으므로 현재 지원 대상이 아니다.

## 실제 기기 검증 매트릭스

각 행은 tested runtime commit, Termux/Android/PRoot 버전, 기기 아키텍처, 실행 날짜를 기록해야 한다.

| 시나리오                | aarch64 | x86_64 | 필수 증거                               |
| ----------------------- | ------- | ------ | --------------------------------------- |
| fresh install           | 대기    | 대기   | digest·checksum, doctor JSON, 실행 로그 |
| 동일 ref 재설치         | 대기    | 대기   | 멱등성, 사용자 파일 보존                |
| 정상 종료               | 대기    | 대기   | 동일 exit code, session/PID 잔존 0      |
| Ctrl-C/SIGTERM          | 대기    | 대기   | terminal 복구, child tree 잔존 0        |
| 로그인 URL              | 대기    | 대기   | browser/clipboard와 URL 파일 삭제       |
| 동시 2세션              | 대기    | 대기   | URL 교차 전달 0                         |
| storage 기본 off        | 대기    | 대기   | HOME 동작, Android storage 미노출       |
| storage opt-in          | 대기    | 대기   | 권한 승인 후 명시적 mount               |
| repair/update/uninstall | 대기    | 대기   | runtime 복구와 프로젝트·credential 보존 |
| checksum failure        | 대기    | 대기   | 설치 중단과 managed file rollback       |

Evidence 파일은 [`docs/termux-evidence/TEMPLATE.md`](./termux-evidence/TEMPLATE.md)를 복사해 `docs/termux-evidence/vX.Y.Z.md`에 두고 다음 필드를 포함한다.

```yaml
status: passed
commit: <40-character-tested-runtime-commit>
tested_at: <ISO-8601>
android: <version>
termux: <version/source>
proot_distro: <version>
architecture: <aarch64-or-x86_64>
```

비밀, 로그인 URL, token, 사용자 절대 경로는 evidence에 기록하지 않는다.

기기 검증이 끝나면 evidence 파일만 추가한 커밋을 만들고 그 커밋에 release tag를 둔다. Release preflight는 evidence의 tested commit이 tag commit의 조상인지, 두 커밋 사이의 유일한 변경 경로가 정확한 `docs/termux-evidence/vX.Y.Z.md`인지 확인한다.

## 알려진 제약

- PRoot는 `ptrace` 기반이므로 파일 시스템 작업이 네이티브 실행보다 느릴 수 있다.
- Android의 Doze/OOM 정책은 장시간 프로세스를 종료하거나 정지시킬 수 있다.
- 공유 저장소는 `termux-setup-storage` 승인과 명시적 `FREEBUFF_STORAGE_BIND=1`이 모두 필요하다.
- 메모리 정보를 읽지 못하면 안전으로 간주하지 않고 `unknown`으로 처리한다.
- 브라우저 intent와 clipboard는 Termux:API 설치·권한·Android 정책에 따라 실패할 수 있다.

## 기기에서 실행할 기본 점검

```bash
freebuff-termux doctor --json
cd ~/test-project
freebuff
```

공유 저장소를 검증할 때만 다음을 사용한다.

```bash
termux-setup-storage
cd /storage/emulated/0/Documents/test-project
FREEBUFF_STORAGE_BIND=1 freebuff
```

전체 실행 절차와 판정 기준은 저장소 루트의 `task-plan.md` P0 검증 추적을 따른다.
