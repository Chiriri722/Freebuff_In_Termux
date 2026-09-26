# FreeBuff in Termux

FreeBuff를 Android Termux에서 PRoot Linux 환경으로 실행하는 호환 레이어입니다. Termux 측 wrapper가 작업 경로, 신호, 로그인 URL을 연결하고 PRoot 내부에는 검증된 Node.js와 고정 버전 FreeBuff를 설치합니다.

현재 상태는 **호스트 결함 9건 수정 완료, 실제 Termux 재검증 대기**입니다. 설치 진입점, stdin·guest URL, CWD, 프로세스 종료와 doctor를 수정하고 독립 보안 리뷰 및 Linux 회귀 검증을 수행했습니다. 상세 결과는 [수정 기록](./docs/reviews/2026-09-08-hardening.md), 후속 개발은 [Spec-kit·플러그인 연동](./docs/DEVELOPMENT_INTEGRATIONS.md)을 참고하세요. 검증되지 않은 `main` 원라인 설치는 제공하지 않습니다.

## 동작 구조

```text
Termux
├─ ~/.local/bin/freebuff
│  ├─ 세션별 private URL bridge
│  ├─ SIGINT/SIGTERM 전달과 child reap
│  └─ ~/project → /root/project 경로 변환
└─ proot-distro login --isolated --shared-home <configured-distro>
   ├─ pinned Node.js + pinned FreeBuff
   └─ /usr/local/bin/xdg-open bridge
```

기본 distro는 Ubuntu이며 설치 시 선택한 값이 `~/.config/freebuff-termux/distro`에 기록됩니다. distro/user 값은 실행 전에 제한된 identifier 문법으로 검증됩니다. [PRoot-Distro v5](https://github.com/termux/proot-distro)의 `list --quiet`·`--isolated`·`--shared-home` 계약을 사용합니다.

## 요구 사항

- F-Droid 계열의 최신 Termux
- 네트워크 연결과 약 1GB 이상의 여유 공간
- aarch64/arm64 또는 x86_64/amd64 기기
- 일반 Termux 사용자 세션. root 실행은 지원하지 않습니다.

설치기는 필요한 패키지만 설치하며 전체 Termux 환경에 `pkg upgrade`를 실행하지 않습니다.

## 설치

### 로컬 checkout에서 설치

릴리스 전에는 검토한 commit을 직접 checkout하는 방식이 가장 명확합니다.

```bash
git clone https://github.com/Chiriri722/Freebuff_In_Termux.git
cd Freebuff_In_Termux
git checkout --detach <40-character-commit-sha>
bash scripts/install.sh ubuntu
```

설치기는 다음 안전 장치를 사용합니다.

- Ubuntu 24.04 또는 Debian 12-slim 공식 OCI image의 multi-platform SHA-256 digest 고정
- Node.js `v22.17.1` arm64/x64 archive의 공식 SHA-256을 installer에 고정
- FreeBuff `0.0.152` archive의 SHA-512 고정 설치
- Termux `util-linux`의 `setsid` 기반 PRoot process-group supervisor
- canonical wrapper/bridge/manager의 원자적 교체
- PRoot image·runtime archive digest를 포함하는 schema 2 관리 manifest와 실패 시 rollback
- manifest ownership 또는 exact installer marker가 없는 기존 runtime root 거부
- 전역 shell rc 파일을 자동 수정하지 않음

`ubuntu`와 `debian` 외의 container 이름을 사용할 때는 mutable image tag를 막기 위해 digest-pinned OCI reference를 명시해야 합니다.

```bash
FREEBUFF_PROOT_IMAGE='registry.example/image@sha256:<64-lowercase-hex>' \
  bash scripts/install.sh custom-name
```

기본값이 아닌 Node.js 또는 FreeBuff 버전은 해당 archive의 검토된 checksum을 함께 제공해야 하며, 이 값은 이후 `repair`를 위해 manifest에 보존됩니다.

```bash
FREEBUFF_NODE_VERSION='vX.Y.Z' \
FREEBUFF_NODE_TARBALL_SHA256='<64-lowercase-hex>' \
FREEBUFF_VERSION='X.Y.Z' \
FREEBUFF_TARBALL_SHA512='<128-lowercase-hex>' \
  bash scripts/install.sh ubuntu
```

`~/.local/bin`이 PATH에 없다면 직접 추가하세요.

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 검증된 remote ref에서 설치

bootstrap은 branch를 거부합니다. 40자리 commit SHA를 쓰거나, version tag와 예상 commit을 함께 제공해야 합니다. 먼저 bootstrap 파일을 내려받아 검토한 뒤 실행합니다.

```bash
export FREEBUFF_TERMUX_REF='<40-character-commit-sha>'
export FREEBUFF_TERMUX_EXPECTED_COMMIT="$FREEBUFF_TERMUX_REF"

curl --fail --location \
  "https://raw.githubusercontent.com/Chiriri722/Freebuff_In_Termux/$FREEBUFF_TERMUX_EXPECTED_COMMIT/scripts/remote-install.sh" \
  --output "$PREFIX/tmp/freebuff-remote-install.sh"

bash "$PREFIX/tmp/freebuff-remote-install.sh" ubuntu
```

version tag를 사용할 때는 `FREEBUFF_TERMUX_EXPECTED_COMMIT`과 Release 페이지에 게시된 `FREEBUFF_TERMUX_ARTIFACT_SHA256`을 모두 지정해야 합니다. bootstrap은 Release archive checksum과 내부 `RELEASE-METADATA`의 tag/commit을 함께 검증합니다. 정식 Release가 생기기 전에는 tag 기반 설치를 stable로 간주하지 않습니다.

## 실행과 storage 권한

Termux HOME 아래 프로젝트는 기본 설정으로 실행됩니다.

```bash
cd ~/my-project
freebuff
```

공유 저장소는 개인정보 노출 범위를 줄이기 위해 기본적으로 bind하지 않습니다. PRoot-Distro v5의 기본 storage 자동 bind를 피하도록 runtime을 `--isolated --shared-home`으로 실행합니다. `/storage/emulated/0` 아래 프로젝트가 꼭 필요할 때만 명시적으로 opt-in합니다.

```bash
termux-setup-storage
cd /storage/emulated/0/Documents/my-project
FREEBUFF_STORAGE_BIND=1 freebuff
```

로그인 URL은 실행별 0700 session 디렉터리의 0600 파일로 전달되고 원자적으로 소비됩니다. 브라우저와 clipboard가 모두 실패해도 URL은 기본적으로 stdout에 출력되지 않습니다. 수동 출력은 `FREEBUFF_URL_ALLOW_PLAINTEXT=1`을 명시한 경우에만 허용됩니다.

Wrapper는 stdin을 보존해 PRoot를 별도 `setsid` process group으로 실행하고 INT/TERM과 기본 5초 grace 뒤 KILL 처리, 정상 종료 후 잔여 group 정리를 수행합니다. `FREEBUFF_KILL_GRACE_SECONDS=0..60`으로 grace를 조정할 수 있습니다.

## 진단과 lifecycle

사람용 진단:

```bash
freebuff-termux doctor
```

에이전트/자동화용 strict JSON 진단:

```bash
freebuff-termux doctor --json
```

종료 코드 계약은 `0=ok`, `1=degraded`, `2=invalid manifest/usage`입니다. schema 2 JSON은 로컬 경로, 로그인 URL, token을 제외합니다. doctor는 개별 manifest 필드와 실제 current runtime 링크 및 실행 파일을 확인합니다. 실제 FreeBuff 로그인 성공은 별도 확인합니다.

```bash
# manifest에 기록된 exact source와 버전으로 복구
freebuff-termux repair

# full SHA 업데이트
freebuff-termux update <40-character-commit-sha>

# tag 업데이트: 예상 commit과 artifact SHA-256이 모두 필수
freebuff-termux update v1.2.3 <40-character-commit-sha> <64-character-artifact-sha256>

# hash가 일치하는 관리 파일만 제거
freebuff-termux uninstall
```

기본 uninstall은 distro, Node/FreeBuff runtime, 프로젝트, FreeBuff 자격 증명을 보존합니다. 수정된 관리 파일도 삭제하지 않고 manifest를 남겨 복구할 수 있게 합니다.

## TypeScript API

인터랙티브 실행에는 `FreeBuffLauncher`를 권장합니다. 명령은 `shell:false` argv로 PRoot에 전달되며 CWD와 FreeBuff 인자는 Bash 코드에 보간되지 않습니다.

```typescript
import { FreeBuffLauncher, checkOomRisk } from 'freebuff-termux';

const oom = checkOomRisk();
if (oom.level === 'unknown' || oom.level === 'danger') {
  throw new Error(oom.message);
}

const launcher = new FreeBuffLauncher();
await launcher.launch('ubuntu', process.cwd(), [], {
  termuxHome: process.env.HOME,
  prootHome: '/root',
  storageBind: false,
});
```

공유 저장소를 TypeScript API로 사용할 때도 `{ storageBind: true }`를 명시해야 합니다. 상세 API는 [Hermes API reference](./skill/freebuff-hermes-integration/references/freebuff_termux_api.md)를 참고하세요.

자동화 실행인 `run()`은 stdout+stderr 합산 1MiB를 기본 상한으로 두며 timeout 또는 `AbortSignal` 취소 시 process group에 TERM을 전달합니다. 기본 5초 뒤 KILL 승격을 수행하고 부모가 먼저 종료해도 POSIX group 정리가 끝날 때까지 기다립니다. 이 기간의 추가 호스트 시그널도 전달합니다. `killGraceMs`와 `maxOutputBytes`는 마지막 controls 인자로 조정할 수 있고, 결과의 `terminationReason`은 `timeout`, `abort`, `output-limit` 중 하나입니다.

## Evidence와 지원 범위

| 항목                               | 현재 evidence                                | 상태             |
| ---------------------------------- | -------------------------------------------- | ---------------- |
| TypeScript build/lint/format       | 2026-09-08 Windows Node 24                   | 통과             |
| Jest unit/contract/doctor JSON     | Linux Node 18/20/22/24 각 185/185            | 통과             |
| Bash syntax                        | 2026-09-08 Linux 개별 검사, 9개              | 통과             |
| ShellCheck/shfmt/actionlint        | 2026-09-08 Linux 전체 검사                   | 통과             |
| Bats shell contracts               | 2026-09-08 Linux 40/40 (full installer 포함) | 통과             |
| npm package payload                | 2026-09-08 packed consumer, exact 55 entries | 통과             |
| GitHub Actions                     | 로컬 workflow 검토                           | 현재 원격 미조회 |
| aarch64 Termux fresh/rerun         | 독립 기기 증거 없음                          | 대기             |
| x86_64 Termux                      | 독립 기기 증거 없음                          | 대기             |
| Ctrl-C/잔존 PID/동시 로그인        | host contract tests                          | 실제 기기 대기   |
| Release artifact/checksum/rollback | 로컬 release Bats / 기기 evidence 없음       | 실제 배포 대기   |

실제 기기 evidence가 없는 조합을 “지원 완료”로 표시하지 않습니다. 상세 작업 상태는 [task-plan.md](./task-plan.md), [progress.md](./progress.md), [findings.md](./findings.md)에 기록됩니다.

## 개발

```bash
npm ci
npm run build
npm run lint
npm run format:check
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand
```

CI는 Node.js 18/20/22 build·test, ESLint/Prettier, npm pack, `bash -n`, ShellCheck warning gate, shfmt, Bats 동적 shell 계약과 root 격리 full-installer hard-crash recovery를 실행합니다.

주요 파일:

- `scripts/install.sh` — canonical installer
- `scripts/remote-install.sh` — immutable-ref bootstrap
- `scripts/freebuff-wrapper.sh` — runtime supervisor
- `scripts/xdg-open-bridge.sh` — login URL bridge
- `scripts/manage.sh` — doctor/update/repair/uninstall
- `skill/freebuff-hermes-integration/` — agent integration guidance

## 라이선스

MIT
