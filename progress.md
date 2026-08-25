# Progress: FreeBuff in Termux hardening

## 2026-08-23

### PR-00 — 계획 채택 및 기준선

- [x] 기존 `docs/task_plan.md`와 `docs/notes.md`를 역사 문서로 확인.
- [x] ChatGPT Pro Library artifact의 새 계획 원문과 20개 findings를 복원.
- [x] 루트 `task-plan.md`, `findings.md`, `progress.md` 생성.
- [x] codebase-memory full graph 생성(370 nodes, 611 edges).
- [x] `npm run build` 통과.
- [x] `npm run lint` 통과.
- [x] `npm run format:check` 통과.
- [x] 샌드박스 밖 `node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand`: 8 suites, 97/97 통과.

### PR-01 — wrapper lifecycle 및 health check

- [x] RED 계약 테스트 작성.
- [x] RED 6/6 실패가 F-001/F-002/F-006 때문임을 확인.
- [x] installer heredoc 동등성 RED 2/2 실패 확인.
- [x] canonical wrapper와 두 installer 생성본의 최소 supervisor 구현.
- [x] health-check argv probe, 안전 카운터, non-login shell 계약 구현.
- [x] 집중 계약 테스트 8/8 통과.
- [x] Git Bash `bash -n` 5개 셸 파일 통과.
- [x] 전체 회귀: 9 suites, 105/105, build/lint/format 통과.
- [!] 실제 Termux 정상/Ctrl-C/잔존 PID 증거는 기기 환경 대기.

### PR-02 — 세션별 URL bridge

- [x] RED 계약 테스트 작성.
- [x] RED 12/12 실패가 고정 파일·URL 정책 부재·비원자적 쓰기 때문임을 확인.
- [x] 세션별 URL bridge 최소 구현.
- [x] 세션별 0700 디렉터리·0600 파일.
- [x] http/https, 길이, 개행·제어문자 정책.
- [x] 원자적 write/consume와 즉시 cleanup.
- [x] canonical/installer bridge 동등성.
- [x] 집중 계약 테스트 20/20 통과.
- [!] 실제 Termux 브라우저 intent·clipboard·동시 세션 증거는 기기 환경 대기.

### PR-03 — TypeScript 실행 계약

- [x] `FreeBuffLauncher` non-login shell·위치 인자·identifier 검증 RED 작성.
- [x] launcher RED 5건과 manager RED 2건 실패 확인.
- [x] 공용 identifier 검증과 고정 Bash/위치 인자 계약 구현.
- [x] `ProotDistroManager`를 `spawnSync(command, args, shell:false)`로 전환.
- [x] 집중 테스트 24/24 GREEN.
- [x] 전체 9 suites, 120/120와 build/lint/format/Bash syntax 회귀 통과.

### PR-04 — path/storage/OOM unknown

- [x] 경로·storage bind·OOM unknown 현재 계약 조사.
- [x] RED 14건으로 임의 절대 경로 PREFIX, 기본/중복 storage, OOM safe, HOME rootfs를 재현.
- [x] 알려진 Termux system root만 PREFIX 변환하고 `/usr`를 정확히 치환.
- [x] storage bind 기본 off·명시적 opt-in·중복 제거 및 storage CWD guard.
- [x] OOM `unknown`, rootfs PREFIX 기본값, distro 검증 구현.
- [x] 집중 테스트 87/87 GREEN.

### PR-05 — installer 공통 코어 + 원자적 설치

- [x] installer RED 계약 6건 확인.
- [x] local installer를 canonical wrapper/bridge 단일 소스로 전환.
- [x] remote bootstrap을 full SHA 또는 tag+expected commit checkout 후 local 위임으로 축소.
- [x] `pkg upgrade` 제거, distro 선검증, Node arch 선택·공식 archive SHA-256 고정.
- [x] Node v22.17.1과 FreeBuff 0.0.152 pin.
- [x] wrapper/bridge/config/manifest 원자 교체와 managed-file rollback 구현.
- [x] health check를 설치된 distro·Node 기반 runtime 계약으로 동기화.
- [x] 전체 9 suites, 124/124, build/lint/format/Bash syntax 통과.
- [!] 실제 Termux fresh/rerun/checksum failure/rollback 증거 대기.

### PR-06 — lifecycle + doctor JSON

- [x] update/repair/uninstall/doctor JSON 계약 설계.
- [x] `manage.sh` 부재 RED 확인.
- [x] manifest를 source하지 않는 key parser와 pinned installer/bootstrap hash 검증.
- [x] `doctor --json` 고정 schema·redaction·0/1/2 종료 코드 구현 및 실행 테스트.
- [x] hash가 일치하는 managed file만 제거하고 distro/runtime/project/credential을 보존하는 uninstall.
- [x] exact source와 version을 재사용하는 repair, ref+commit을 검증하는 update.
- [x] 전체 10 suites, 128/128, build/lint/format/Bash syntax 통과.
- [!] 실제 Termux update/repair/uninstall lifecycle 증거 대기.

### PR-07 — shell/CI gates

- [x] CI shell syntax·ShellCheck 게이트 설계.
- [x] 6개 canonical shell entrypoint를 독립 CI job에 추가.
- [x] 공식 ShellCheck v0.11.0 zip SHA-256 검증 후 로컬 warning gate PASS.
- [x] CI workflow contract test GREEN.
- [!] GitHub required check/branch protection과 runner 실행 증거 대기.

### PR-08 — README/Hermes/API 문서

- [x] 문서 RED 4건 확인.
- [x] mutable main pipe 제거, immutable install/lifecycle/storage opt-in/evidence 문서화.
- [x] Hermes unknown OOM·configured distro·doctor JSON 계약 반영.
- [x] API reference를 structured runner/storageBind/OOM unknown에 동기화.
- [x] 문서 smoke 계약 4/4 GREEN.

### PR-09 — release workflow

- [x] release 공급망 RED 확인.
- [x] tag/package 버전, tested runtime evidence, evidence-only tag commit, 전체 quality gate를 Release 조건으로 추가.
- [x] metadata 포함 artifact·SHA-256·script checksum과 `gh release create` workflow 구현.
- [x] tag bootstrap을 expected artifact SHA-256 + metadata tag/commit 검증으로 전환.
- [x] CHANGELOG Unreleased 추가, release 계약 4/4 GREEN.
- [!] 실제 Termux evidence, tag, GitHub Release는 아직 없음.

### Host P1 closure — runtime·package·PRoot v5

- [x] `createNodeSpawner`의 timeout·AbortSignal·합산 출력 예산·TERM→KILL·Linux process-group 계약.
- [x] shell wrapper를 `setsid --wait` 전용 process group supervisor로 전환하고 0~60초 grace 뒤 KILL·reap 구현.
- [x] spawn 직전/직후 AbortSignal 경쟁 조건과 signal listener cleanup 회귀.
- [x] npm ESM exports/types/files allowlist·prepack·Node engine·support metadata.
- [x] `npm pack --dry-run --json` 52-entry payload 검증.
- [x] 존재하지 않는 custom bind source를 `BIND_MOUNT_NOT_FOUND`로 구조화.
- [x] PATH probe, Android version, wake/storage 명령, storage 디렉터리 확인에서 셸 문자열 실행 제거.
- [x] PRoot-Distro v5의 `list --quiet`·`--isolated --shared-home` 계약 반영.
- [x] Ubuntu 24.04·Debian 12-slim OCI rootfs digest pin과 custom image digest 검증.
- [x] install manifest schema 2와 `proot_image` 검증, invalid doctor strict JSON.
- [x] GitHub Actions dependency commit SHA pin, shfmt와 Bats CI gate.
- [x] codebase-memory final fast reindex: 478 nodes, 750 edges.
- [x] 실제 기기 기록을 위한 redacted `docs/termux-evidence/TEMPLATE.md` 추가.
- [!] 실제 Termux·PRoot signal tree와 GitHub runner evidence는 환경 대기.

### Pro H-01~H-06 host gap closure

- [x] agbrowse summary-only 협업으로 Pro gap audit 회수.
- [x] malicious manifest/user-file ownership RED 재현 후 path/hash contract로 mutation 차단.
- [x] `/usr/local/bin` global runtime link 제거와 project-owned `/opt/freebuff-termux/current-*` 전환.
- [x] FreeBuff npm tarball SHA-512 pin과 custom version checksum 강제.
- [x] context-bound installer transaction, hard-exit recovery, commit, mismatch, stale staging Bats 4/4.
- [x] exact npm payload allowlist와 clean packed-consumer import/CLI smoke 1/1.
- [x] self-referential evidence gate를 tested runtime + evidence-only tag commit 모델로 수정.
- [x] release preflight/artifact tamper negative suite Bats 7/7.
- [x] Windows shell Bats 19 pass/1 skip 기준선 확보 후 실제 Linux full-installer·동시성 확장까지 26/26 통과.
- [x] host signal forwarding의 TERM→KILL RED→GREEN과 Linux-only real process Jest 3건 추가.
- [x] Linux-only Jest 3건·setsid child/grandchild 1건은 Podman WSL2 Linux에서 통과.
- [x] full installer hard-crash failpoint는 Linux root 격리에서 통과.
- [!] 실제 Termux lifecycle은 기기 환경 대기.

### Linux dynamic closure — Podman WSL2 / Node 22.17.1

- [x] Podman WSL2 Linux 경로 발견; Debian 12, util-linux `setsid` 2.38.1 확인.
- [x] Linux overlay에서 `npm ci` 후 실제 process-group Jest 3/3 통과.
- [x] PGID 게시 직후 early TERM 무한 대기 RED 재현.
- [x] early TERM도 bounded group cleanup을 사용하도록 wrapper GREEN 수정.
- [x] Linux shell Bats 26/26 통과(full installer 포함), child/grandchild 잔존 0.
- [x] 환경 의존 `HOME` 테스트를 명시적 Termux/PRoot home 계약으로 교정.
- [x] Node 22.17.1 Linux 전체 Jest 16 suites, 175/175 통과.
- [x] 실제 installer 5개 transactional stage의 hard-crash recovery와 TERM rollback 통과.
- [x] CI/Release에 root installer integration gate 추가, workflow contract·actionlint 통과.
- [x] Linux full release artifact 67 entries·8 script checksums·SHA sidecar 검증 통과.
- [x] `npm audit`: 414 dependencies, vulnerabilities 0.
- [x] GitHub 원격 읽기 감사: 기존 baseline CI success, tag/Release 0, main protection 없음.
- [!] 새 변경의 GitHub runner와 실제 Termux/Android evidence는 commit/push·기기 실행 대기.

### Host gap closure II — runtime ownership·checksum·URL isolation

- [x] 공식 Node v22.17.1 `SHASUMS256.txt`에서 arm64/x64 archive digest를 확인하고 installer에 독립 고정.
- [x] custom Node checksum 필수화, Node/FreeBuff archive checksum을 manifest와 repair 환경에 보존.
- [x] 현 manifest 소유 또는 exact installer marker가 없는 pre-existing runtime root 거부 RED→GREEN.
- [x] full installer transaction의 5개 mutation stage를 SIGKILL·SIGTERM 각각 검증하고 old-set/user sentinel 복원.
- [x] 두 wrapper 동시 실행에서 session URL 교차 전달 0을 Linux에서 동적 확인.
- [x] URL bridge의 slash-matching glob traversal RED를 exact session-path regex로 차단.
- [x] clean npm consumer에서 packaged lifecycle manager `doctor --json`까지 source checkout 없이 실행.
- [x] Linux 전체 Jest 175/175, Bats 26/26, Windows coverage 172 pass/3 Linux-only skip.

### 실행 로그 요약

| 명령                              | 결과               |
| --------------------------------- | ------------------ |
| `npm run build`                   | PASS               |
| `npm run lint`                    | PASS               |
| `npm run format:check`            | PASS               |
| Jest 기본 병렬(샌드박스)          | EPERM — 환경 제약  |
| Windows Jest coverage             | PASS 172, SKIP 3   |
| Linux Node 22 Jest                | PASS 175/175       |
| Git Bash `bash -n` 9개 파일       | PASS               |
| ShellCheck v0.11.0 warning        | PASS 9개 파일      |
| shfmt v3.13.1 diff                | PASS 9개 파일      |
| Linux Bats v1.14.0                | PASS 26/26         |
| Full installer failpoint matrix   | PASS 5 stages × 2 signals |
| npm pack + clean consumer         | PASS 55 entries    |
| GitHub workflow/actionlint 1.7.12 | PASS 2개 파일      |
| Linux release artifact            | PASS 67 entries    |
| GitHub baseline CI                | PASS, old SHA only |
| GitHub tag/release/protection      | 0/0/none           |

### 다음 행동

1. aarch64 Termux에서 fresh/rerun·signal tree·URL bridge·lifecycle evidence를 수집한다.
2. 변경을 검토·커밋·push해 새 GitHub runner 결과를 확보한다.
3. runner 성공 뒤 required checks와 branch protection을 적용한다.
4. 실제 Termux evidence 없이는 PR-10 Release를 진행하지 않는다.
