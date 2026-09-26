# 아키텍처: FreeBuff in Termux

> 2026-09-08 후속 수정 기준이다. F-033~F-041의 호스트 수정 및 독립 리뷰 결과는 [수정 기록](./reviews/2026-09-08-hardening.md)에 있다. 실제 Android 검증은 별도다.

## 목적과 경계

FreeBuff in Termux는 Android용 네이티브 포트가 아니라 Termux와 PRoot Linux 사이의 실행·설치·인증 URL 브리지다. Termux wrapper가 사용자 프로젝트와 터미널을 소유하고, PRoot 안의 digest-pinned Linux rootfs에서 고정 버전 Node.js와 FreeBuff를 실행한다.

실제 Android 커널, Termux 권한, PRoot의 signal 전달은 Windows 호스트 테스트로 완전히 재현할 수 없다. 따라서 호스트 계약과 실제 기기 evidence를 구분한다.

## 런타임 구조

```text
Termux
├─ ~/.local/bin/freebuff
│  ├─ distro/config 검증
│  ├─ private URL session 생성
│  ├─ PRoot child 감시와 signal 전달
│  └─ 종료 시 watcher/session 정리
├─ ~/.local/bin/freebuff-termux
│  └─ doctor/update/repair/uninstall
└─ proot-distro login --isolated --shared-home <distro>
   ├─ /root                 ← Termux HOME의 명시적 shared-home
   ├─ /storage/emulated/0   ← FREEBUFF_STORAGE_BIND=1일 때만 추가
   ├─ /opt/freebuff-termux  ← pinned Node.js와 FreeBuff
   └─ /usr/local/bin/xdg-open → private URL bridge
```

PRoot-Distro v5의 기본 로그인은 Android 공유 저장소를 자동 노출할 수 있다. 이 프로젝트는 `--isolated --shared-home`을 사용해 HOME 프로젝트만 명시적으로 공유하고, Android storage는 opt-in으로 유지한다.

## 설치 공급망

Canonical installer인 `scripts/install.sh`는 다음 불변 조건을 적용한다.

- Ubuntu 24.04 또는 Debian 12-slim 공식 multi-platform OCI image를 SHA-256 digest로 고정한다.
- 사용자 지정 distro는 `FREEBUFF_PROOT_IMAGE=image@sha256:<digest>`가 없으면 거부한다.
- Node.js v22.17.1 arm64/x64 archive의 공식 SHA-256을 installer에 고정하고 custom version은 명시 checksum을 요구한다.
- FreeBuff npm 버전과 archive SHA-512를 고정한다.
- versioned runtime root는 현 manifest ownership 또는 archive digest marker가 없으면 신뢰하지 않는다.
- wrapper, manager, URL bridge, config, schema 2 manifest를 원자적으로 교체한다.
- manifest는 설치한 OCI image와 runtime archive digest를 기록하며 doctor/repair/update가 다시 검증한다.
- 설치 실패 시 이번 실행이 변경한 managed file을 rollback한다.
- 전체 Termux 환경에 `pkg upgrade`를 실행하지 않는다.

Remote bootstrap은 full commit SHA 또는 tag+expected commit만 받는다. Tag 설치는 GitHub Release artifact의 예상 SHA-256과 내부 `RELEASE-METADATA`를 함께 검증한다.

## 실행 계약

TypeScript 경로와 shell wrapper는 공통 원칙을 따른다.

- distro와 user는 제한된 identifier 문법으로 검증한다.
- CWD와 FreeBuff 인자는 Bash 코드가 아니라 별도 argv/위치 인자로 전달한다.
- CWD 이동 실패는 세 실행 경로 모두에서 즉시 종료로 전파한다.
- PRoot 내부 셸은 `/bin/bash --norc --noprofile -c`다.
- PATH는 `/opt/freebuff-termux/current-freebuff/bin`과 `current-node/bin`을 시스템 경로보다 우선한다.
- TypeScript 기본 spawner는 Linux process group을 만들고 TERM 후 grace 기간이 지나면 KILL한다.
- 직접 자식이 먼저 종료돼도 예약된 group escalation과 호스트 signal handler를 완료 시점까지 유지한다.
- shell wrapper는 `setsid --wait`로 PRoot 전용 process group을 만들고 INT/TERM 뒤 제한된 grace와 KILL·reap을 적용한다.
- 래퍼는 stdin FD를 명시적으로 전달하고, 정상 종료 후에도 PGID를 유지해 후손을 정리한다.
- pipe 출력은 stdout+stderr 합산 바이트 예산을 가진다.

## 경로와 storage

```text
/data/data/com.termux/files/home/project  → /root/project
/storage/emulated/0/Documents/project    → 같은 경로(storage opt-in 필요)
기타 절대 경로                           → 자동 재작성하지 않음
```

Custom bind source는 host에 실제로 존재해야 하며, 없으면 `BindMountError`와 `BIND_MOUNT_NOT_FOUND` 코드로 실행 전에 실패한다.

## 로그인 URL

각 실행은 Termux HOME 아래 0700 session 디렉터리와 0600 queue 파일을 사용한다. PRoot의 `xdg-open` bridge는 http/https, 4096바이트, 제어문자 금지 정책을 통과한 URL만 원자적으로 기록한다. Wrapper는 파일을 한 번 claim한 뒤 브라우저 또는 clipboard로 전달하고 즉시 삭제한다. URL plaintext 출력은 명시적 opt-in이다.

호스트는 `$HOME/.cache/freebuff-termux/sessions/session.XXXXXX/login-url`을 소비하고
게스트는 `/root/.cache/freebuff-termux/sessions/session.XXXXXX/login-url`에 기록한다.
두 경로는 `--shared-home`의 동일한 파일을 가리킨다. 실제 Linux PRoot의 HOME bind와
브리지 파일 기록을 검증했으며 Android 브라우저/clipboard 전달은 실기기 항목이다.

## 검증 계층

- TypeScript: Jest unit/contract tests, build, ESLint, Prettier
- Shell: Bash syntax, ShellCheck warning gate, shfmt, Bats 동적 계약
- Packaging: npm allowlist와 `npm pack --dry-run`
- Release: tested runtime commit의 Termux evidence, evidence-only tag commit, tag/package 정합, 최종 artifact checksum 재검증
- Device: fresh/rerun, browser/clipboard, Ctrl-C/잔존 PID, lifecycle 보존을 실제 Termux에서 별도 수집

현재 지원 상태는 [ANDROID_COMPATIBILITY.md](./ANDROID_COMPATIBILITY.md), [최신 진행 기록](../progress.md), [코드 리뷰](./reviews/2026-09-08.md)를 기준으로 한다.
