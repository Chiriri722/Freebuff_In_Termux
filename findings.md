# Findings: FreeBuff in Termux hardening

## 현재 리뷰 — 2026-09-08

`main@979bb2b8230d68c68e86e7a69e6305c82b74ead1`의 [상세 리뷰와 인계](./docs/reviews/2026-09-08.md)에 F-033~F-041을 기록했다. P1은 실행 권한, wrapper stdin, guest URL 경로, CWD 실패 후 실행, TypeScript 손자 cleanup의 5건이다. P2는 wrapper 정상 종료 cleanup, doctor validation, runtime 링크 진단, 기존 테스트 실패의 4건이다.

F-033~F-041은 후속 작업에서 수정했다. [수정·검증 기록](./docs/reviews/2026-09-08-hardening.md)에
재현, 독립 리뷰 추가 지적과 조치, 호스트 결과를 기록했다. Spec-kit 명세와 Linear 이슈는
[개발 연동](./docs/DEVELOPMENT_INTEGRATIONS.md)에서 연결한다. 아래는 발견 당시의 역사 기록이다.

## 2026-08-23 — 기준선

- 저장소: `Chiriri722/Freebuff_In_Termux`
- 기준 커밋: `4c6e746fa7e1d9892383403ce47c2ae2211a4a2d`
- working tree는 시작 시 깨끗했다.
- 호스트 build, lint, format은 통과했다.
- Jest는 샌드박스에서 child process EPERM이 발생했으나, 샌드박스 밖 `--runInBand` 실행은 8 suites, 97/97 통과했다.
- Git tag와 GitHub Release가 없다.

## 코드 구조

- 실제 사용 경로: `scripts/freebuff-wrapper.sh` → `proot-distro login` → PRoot 내부 `freebuff`.
- 프로그래밍 경로: `FreeBuffLauncher`(비동기 spawn)와 `ProotDistroManager`(동기 spawn)가 공통 shell-free argv 계약으로 PRoot 명령을 만든다.
- wrapper/bridge 설치 내용이 독립 파일과 installer heredoc에 중복되어 드리프트 위험이 있다.
- 코드 지식 그래프 기준 hotspot은 `isTermux`, `termuxToProot`, `normalizePathForTermux`, `execInDistro`, `buildBindMountArgs`다.

## 재현된 P0

### F-001 — watcher 조기 종료

`scripts/freebuff-wrapper.sh`는 `set -euo pipefail` 아래에서 `count=0`으로 시작해 `((count++))`를 실행한다. Bash 산술 명령은 평가 결과가 0이면 상태 1을 반환하므로 첫 반복 뒤 watcher가 종료될 수 있다.

### F-002 — cleanup 우회

wrapper는 watcher 시작 후 EXIT trap을 등록하지만 마지막에 `exec proot-distro ...`를 호출한다. 성공한 `exec`는 shell을 교체하므로 shell EXIT cleanup을 실행하지 않는다.

### F-005 — shell 계약 드리프트

- 실제 wrapper: `/bin/bash --norc --noprofile -c`
- `FreeBuffLauncher.buildCommand`: `bash -lc`
- `ProotDistroManager.execInDistro`: `bash -lc`
- `health_check.sh`: `bash -lc`

실기기에서 해결했던 proot-distro v5 PATH/profile 문제를 TypeScript와 진단 경로가 다시 도입할 수 있다.

### F-006 — health check 조기 종료 및 eval

`health_check.sh`도 `set -e` 아래 `((PASS++))`/`((FAIL++))`를 사용한다. 첫 성공 또는 실패에서 조기 종료할 수 있으며, 문자열 명령을 `eval`로 실행한다.

## Pro 협업

- 기존 대화의 Library에 있는 1,075줄 `task-plan.md`를 agbrowse로 복원했다.
- Pro 계획은 `implementation_started: false`, Phase 0 시작 상태였다.
- 원자 순서는 PR-00 계획 채택 → PR-01 lifecycle/health check → PR-02 세션 URL → PR-03 CommandSpec이다.
- Pro 후속 응답은 원본 SHA-256을 `8b241c73c101b476235758fbe498930a4852c1d2bca92ea29a291908da853266`으로 제시하고, PR-01에 두 installer의 wrapper heredoc 동등성까지 포함하라고 권고했다.

## PR-01 호스트 결과

- canonical wrapper와 `install.sh`·`remote-install.sh` 생성본 모두 watcher 안전 증가, supervisor `wait`, INT/TERM 전달, cleanup reap 계약을 갖는다.
- health check는 `eval` 대신 argv를 실행하고 카운터를 대입식으로 증가시킨다.
- health check의 PRoot probe는 실제 wrapper와 같은 `/bin/bash --norc --noprofile -c`를 사용한다.
- Git Bash `bash -n`은 wrapper, local/remote installer, xdg bridge, health check 전부 통과했다.
- 전체 호스트 검증은 9 suites, 105/105 tests, build/lint/format 통과다.

## PR-02 호스트 결과

- URL bridge는 실행별 private session 디렉터리와 0600 queue 파일을 사용한다.
- xdg bridge는 http/https·4096바이트·제어문자 정책을 적용하고 임시 파일을 원자적으로 교체한다.
- canonical 스크립트와 두 installer heredoc에 동일한 계약 테스트를 적용했다.

## PR-03 호스트 결과

- `FreeBuffLauncher`와 `ProotDistroManager` 모두 `/bin/bash --norc --noprofile -c`를 사용한다.
- CWD와 FreeBuff 인자는 Bash 코드에 보간되지 않고 위치 인자로 전달된다.
- distro/user는 제한된 identifier 문법으로 검증된다.
- 동기 runner는 `spawnSync(command, args, shell:false)`를 사용하며, 구형 주입 runner에는 위험한 shell fallback 대신 명시적 오류를 반환한다.
- 최종 호스트 검증은 9 suites, 120/120 tests, build/lint/format, Bash syntax 전부 통과다.

## PR-04 호스트 결과

- `resolvePath`는 `/usr`와 알려진 Termux system root만 PREFIX로 변환하고 Android/사용자 절대 경로는 보존한다.
- TypeScript storage bind는 기본 비활성이고 명시적 활성·중복 제거·storage CWD guard를 적용한다.
- 메모리 판독 실패는 `safe`가 아니라 `unknown`이며 rootfs 기본 경로는 HOME가 아닌 Termux PREFIX다.

## PR-05 호스트 결과

- 두 installer의 wrapper/bridge heredoc을 제거하고 canonical 파일만 설치한다.
- remote bootstrap은 branch를 받지 않으며 full SHA 또는 tag와 expected commit 쌍을 검증한다.
- installer는 전체 `pkg upgrade`를 하지 않고, Node 아키텍처별 archive의 공식 SHA-256을 코드에 고정한다.
- Node v22.17.1과 FreeBuff 0.0.152를 고정하고 managed file manifest·원자 교체·rollback을 추가했다.
- 전체 호스트 검증은 9 suites, 124/124 tests, build/lint/format, Bash syntax 전부 통과다.

## PR-06 호스트 결과

- 설치기는 canonical `manage.sh`를 함께 배포하고 hash·source·version을 manifest에 기록한다.
- `doctor --json`은 경로와 URL을 노출하지 않는 고정 schema를 출력하고 ok/degraded/invalid를 종료 코드 0/1/2로 구분한다.
- repair/update는 manifest에 기록된 installer/bootstrap hash를 검증한 뒤 실행한다.
- uninstall은 수정되지 않은 managed file만 제거하고 distro, runtime, 프로젝트, 인증 자료는 기본적으로 보존한다.
- 전체 호스트 검증은 10 suites, 128/128 tests, build/lint/format, Bash syntax 전부 통과다.

## PR-07~PR-09 호스트 결과

- CI에 6개 shell entrypoint의 Bash syntax·ShellCheck·shfmt·Bats gate를 추가했고, 공식 ShellCheck v0.11.0과 shfmt v3.12.0 binary checksum 확인 후 로컬에서도 통과했다.
- README/Hermes/API는 immutable install, lifecycle, storage opt-in, OOM unknown, evidence 등급을 동일하게 설명한다.
- Release workflow는 tag/package 정합, tested runtime commit의 `status: passed` Termux evidence, evidence-only tag commit 없이는 artifact와 GitHub Release를 만들지 않는다.
- tag bootstrap은 expected artifact SHA-256과 `RELEASE-METADATA` tag/commit을 모두 검증한다.

## Host P1 closure 결과

- 비동기 launcher는 합산 stdout/stderr 기본 1MiB 예산, timeout·AbortSignal, TERM→KILL grace, Linux process group, listener/timer cleanup을 제공한다.
- shell wrapper도 `setsid --wait`로 PRoot를 별도 process group에 두고 INT/TERM 후 제한된 grace를 거쳐 group KILL·reap한다.
- process spawn과 AbortSignal 등록 사이의 경쟁 조건도 회귀 테스트로 재현하고 차단했다.
- npm package는 ESM entry/types/exports/files allowlist와 prepack build를 선언하며 dry-run payload는 52개 엔트리다.
- custom bind source가 없으면 `BindMountError(code=BIND_MOUNT_NOT_FOUND)`를 반환한다.
- host 명령 probe의 `execSync`와 HOME 문자열 shell 실행을 모두 제거하고 `spawnSync/execFileSync(shell:false)`, PATH scan, filesystem API로 교체했다.
- PRoot-Distro v5는 `list --quiet`과 `--isolated --shared-home`을 사용해 Termux HOME만 공유하고 Android storage 기본 노출을 피한다.
- Ubuntu 24.04와 Debian 12-slim rootfs는 multi-platform OCI digest로 고정되며 custom image도 `@sha256:` 형식만 허용한다.
- install manifest schema 2는 `proot_image`를 필수로 검증하고 `doctor --json` invalid 경로는 stderr 없이 단일 redacted JSON만 출력한다.
- GitHub Actions는 action dependency를 commit SHA로 고정했고 CI/release workflow는 YAML parse, actionlint 1.7.12, 계약 테스트를 통과했다.
- 당시 호스트 회귀는 14 suites, 162/162 Jest, build/lint/format, Bash syntax, ShellCheck 6개, shfmt 6개, Bats 8 pass/1 skip, npm pack 52-entry였다. 이후 Pro gap closure 결과는 아래에 갱신한다.

## 증거 등급 제한

- 현재 결과는 로컬 Windows 호스트와 정적 Bash 검토 증거다.
- 실제 Termux/Android의 browser intent, clipboard fallback, PRoot signal tree, storage permission은 아직 이번 세션에서 재검증하지 않았다.

## Pro 2차 gap audit 및 host closure

- agbrowse로 기존 Pro 대화에 현재 구현·검증 요약을 보내 H-01~H-06 gap audit을 회수했다. 광범위한 저장소 업로드는 하지 않았다.
- manifest 경로와 hash를 mutation 전에 검증하고, 기존 distro adoption은 `FREEBUFF_ALLOW_EXISTING_DISTRO=1` 없이는 거부한다. 전역 `/usr/local/bin` runtime link도 제거했다.
- FreeBuff 0.0.152 tarball의 SHA-512를 고정하고 custom version은 caller-supplied SHA-512 없이는 설치하지 않는다.
- context-bound installer transaction은 hard exit 뒤 managed file old-set 전체를 복원하고 context mismatch에는 아무 파일도 건드리지 않는다.
- npm tarball은 exact 55-entry allowlist로 제한되며 빈 consumer 프로젝트에 실제 설치한 뒤 public import와 packaged CLI를 실행한다.
- 기존 release evidence gate는 evidence 파일이 자기 자신을 포함한 commit SHA를 요구해 충족 불가능했다. 이제 tested runtime commit의 evidence-only 자손에 tag를 두고 ancestry와 exact changed path를 검사한다.
- 최종 release tar.gz는 package 단계에서 독립 캡처한 SHA-256, archive root/path, metadata, packaged version을 upload 전에 다시 검증한다.
- 호스트 SIGINT/SIGTERM forwarding도 bounded grace 뒤 KILL로 승격한다. Linux 전용 stdout/stderr aggregate limit, timeout/abort, child/grandchild 잔존 0은 Podman WSL2에서 통과했으며 새 GitHub runner 증거만 대기다.
- Windows 회귀는 build/lint/format, Jest 172 pass/3 Linux-only skip, Bash/ShellCheck/shfmt 9개, Bats 19 pass/1 Linux skip, actionlint 2 workflow, npm pack exact 55 entries가 통과했다.

## Linux 동적 closure와 원격 감사

- 실행 중인 Podman WSL2 machine(kernel 6.6.87.2)과 설치 대상과 같은 Node 22.17.1 Debian 12 이미지를 사용했다. Windows `node_modules`는 재사용하지 않고 lockfile로 386 packages를 Linux overlay에 새 설치했다.
- 전체 Jest는 Linux에서 16 suites, 175/175가 통과했고 package-consumer도 실제 pack/install/import/CLI를 수행했다. `npm audit`은 414 dependencies에서 취약점 0을 보고했다.
- 실제 process-group 테스트는 aggregate stdout/stderr 6-byte limit, timeout TERM→KILL, AbortSignal, child/grandchild 잔존 0을 모두 통과했다.
- Linux `setsid --wait` Bats가 PGID 게시 직후 TERM 경합에서 실제 무한 대기를 발견했다. early-signal 분기도 `stop_freebuff_group`으로 승격한 뒤 full-installer 통합을 포함한 shell Bats 26/26이 통과했다.
- 실제 `install.sh`는 root 격리 Termux 경로에서 5개 transactional mutation stage 각각을 SIGKILL·SIGTERM으로 중단해 wrapper·manager·bridge·config·manifest·runtime links·user sentinel 전체 old-set 복원을 확인했다.
- full release artifact를 Linux에서 조립해 67 archive entries, 8 script checksums, metadata/package version, 독립 SHA-256과 sidecar를 검증했다.
- GitHub 원격 `main`은 여전히 `4c6e746f...`이고 해당 기존 CI run은 성공이다. 새 로컬 변경에 대한 run은 없으며 tag/Release는 0, main branch protection은 404 `Branch not protected`다.

## Host gap closure II

- 기본 Node v22.17.1의 arm64/x64 archive SHA-256을 공식 upstream 목록에서 확인해 코드에 고정했다. custom Node는 별도 SHA-256 없이는 설치되지 않는다.
- 기존 installer는 versioned runtime root에 실행 파일만 있으면 checksum download를 건너뛰었다. 이제 현 manifest ownership 또는 archive digest가 포함된 exact `.freebuff-termux-runtime` marker가 없으면 거부한다.
- custom Node/FreeBuff archive checksum은 schema 2 manifest에 기록되고 `repair`가 원래 installer 환경으로 다시 전달한다. legacy default-version manifest의 누락 값은 기존 default pin으로만 호환한다.
- URL bridge의 `session.*` shell glob은 slash까지 삼켜 traversal 문자열을 허용했다. 6자리 alphanumeric mktemp suffix 전체 경로 정규식으로 수정했다.
- 두 wrapper 동시 실행의 URL 교차 전달 0과 packaged lifecycle `doctor --json`을 Linux clean-consumer 경계에서 확인했다.
