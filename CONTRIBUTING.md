# 기여 및 후속 개발

[현재 작업 계획](./task-plan.md)과 [2026-09-08 리뷰](./docs/reviews/2026-09-08.md)를 먼저 확인한다. 내부 문서의 역할은 [문서 안내](./docs/README.md)에 정리되어 있다. 현재는 새 기능보다 설치·실행·종료·진단 결함의 회귀 수정이 우선이다.

## 로컬 검증

lockfile을 기준으로 의존성을 설치하고 다음 검사를 실행한다.

```bash
npm ci
npm run build
npm run lint
npm run format:check
node --experimental-vm-modules node_modules/jest/bin/jest.js --runInBand
node dist/index.js
```

마지막 명령은 환경 정보 CLI smoke다. 실제 FreeBuff 실행이나 Termux 호환성 검증을 대신하지 않는다. `npm test -- --runInBand`의 인자를 호스트 npm wrapper가 소비하면 위처럼 Jest CLI를 직접 실행한다.

F-033~F-041 수정 후 Linux Node 24.14.0에서 Jest 185/185가 통과했다.
최신 Windows 및 Node 매트릭스 결과는 [수정 기록](./docs/reviews/2026-09-08-hardening.md)을 따른다.
Spec-kit, Linear, Codex Security와 Sentry 사용법은 [개발 연동](./docs/DEVELOPMENT_INTEGRATIONS.md)에 있다.
설치되는 guest Node v22.17.1과 실제 Android 동작은 별도로 검증한다.

## 변경에 맞는 경계 검사

| 변경                        | 추가 확인                                                                                       |
| --------------------------- | ----------------------------------------------------------------------------------------------- |
| TypeScript launcher/spawner | argv, 실패 CWD, stdin, 출력 제한, 취소, 부모 선종료·손자 생존                                   |
| shell wrapper/URL bridge    | Bash 구문, ShellCheck/shfmt, Bats, PTY와 실제 guest URL queue                                   |
| installer/manager           | Git 실행 mode, fresh/rerun, 각 transaction failpoint, 사용자 파일 보존, doctor invalid/degraded |
| package/export              | `npm run test:package-consumer`, exact payload allowlist, 빈 소비자 import/CLI                  |
| release                     | tag/package, tested commit→evidence-only commit, artifact checksum                              |
| 문서                        | Prettier, 상대 링크, `tests/docs-contracts.test.ts`; 동작 보장과 evidence 일치                  |

production shell 파일마다 개별로 `bash -n`을 실행한다. `bash -n file1 file2`는 두 번째 파일을 첫 번째 스크립트의 인자로 취급하므로 여러 파일 검증이 아니다.

```bash
find scripts skill/freebuff-hermes-integration/scripts -type f -name '*.sh' \
  -exec bash -n {} \;
bats tests/shell
```

ShellCheck/shfmt의 대상과 옵션은 [CI workflow](./.github/workflows/ci.yml)를 따른다. full installer fixture는 `/data/data/...` 테스트 경로를 생성하므로 **일회성 Linux root 컨테이너 안에서만** 다음 명령을 실행한다.

```bash
FREEBUFF_RUN_INSTALLER_INTEGRATION=1 bats tests/shell/installer-integration.bats
```

문서는 저장소에 설치된 Prettier로 검사한다. `npm run format:check`는 TypeScript만 포함한다.

```bash
node node_modules/prettier/bin/prettier.cjs --write README.md CONTRIBUTING.md docs/README.md
```

## 구현 원칙

- public API는 `src/index.ts`가 export한다. 이 파일에는 직접 실행 시 환경 진단도 있다.
- `src/proot/`는 실행·경로·PRoot 연동, `src/utils/`는 환경·경로·메모리·Termux 명령을 담당한다.
- 외부 실행·파일 시스템은 주입 가능한 경계를 활용한다. mock의 문자열 검사만으로 실제 Bash/guest/process 계약을 대체하지 않는다.
- 사용자 경로와 인자는 argv/위치 인자로 전달하고, 작업 디렉터리 진입 실패를 명시적으로 처리한다.
- 프로젝트·자격 증명·수정된 사용자 파일을 보존한다. source checkout 권한과 release 파일 권한도 실행 계약이다.
- 호스트, Linux fixture, 실제 PRoot, 실제 Android evidence를 구분한다.

## 실제 Termux와 릴리스

호스트 결함을 수정한 runtime commit으로 [기기 evidence 양식](./docs/termux-evidence/TEMPLATE.md)의 전체 항목을 실행한다. 단순 `--version` 성공만으로 지원 완료를 표시하지 않는다. 민감한 URL/token과 사용자 절대 경로는 기록하지 않는다.

검증한 runtime 이후 exact evidence 파일만 바뀐 커밋에 release tag를 두는 계약은 [아키텍처](./docs/ARCHITECTURE.md)와 `scripts/release-preflight.sh`를 따른다. 현재 `package.json` 버전은 `1.0.0`이며 기존 커밋 제목의 `v.0.1.5`를 그대로 tag로 쓰면 버전이 맞지 않는다.

커밋은 `type(scope): description` 형식으로 문제와 결과를 적는다. 코드 리뷰에는 재현 조건, 변경한 동작, 실행한 검증, 남은 기기 검증을 포함한다.
