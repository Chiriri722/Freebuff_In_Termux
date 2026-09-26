# 개발 연동: Spec-kit, Codex Security, Linear, Sentry

현재 수정 명세는 [runtime hardening](../specs/001-runtime-hardening/spec.md)이며,
연결 식별자는 [development-integrations.json](../config/development-integrations.json)에 기록한다.
이 설정은 개발 작업 추적용이고 배포 패키지에 포함되지 않는다.

## Spec-kit

[공식 Spec-kit](https://github.com/github/spec-kit/tree/v1.0.0) v1.0.0의
Codex 스킬 10개와 PowerShell 워크플로를 설치했다. 고정 커밋은
`bca679051abb80d6cf0cd909f2539a28a10eb7eb`이다.

```powershell
uv tool run --from git+https://github.com/github/spec-kit.git@v1.0.0 specify check
$env:SPECIFY_FEATURE_DIRECTORY = 'specs/001-runtime-hardening'
.\.specify\scripts\powershell\check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks
```

Codex를 레포 폴더에서 시작하면 `.agents/skills`의 `$speckit-specify`,
`$speckit-plan`, `$speckit-tasks`, `$speckit-implement`, `$speckit-converge`를
사용할 수 있다. 원칙은 [constitution](../.specify/memory/constitution.md)에 있다.
기존 작업을 추적할 때는 새 명세를 중복 생성하지 않고 활성 spec의 tasks를 갱신한다.
`taskstoissues`의 기본 GitHub 발행은 이번 작업에 사용하지 않는다. 이슈 추적은 Linear를 사용한다.

## Linear와 Codex Security

[FreeBuff Termux 프로젝트](https://linear.app/david-lee-722/project/freebuff-termux-d6b62b69085a)에
F033–F041을 개별 이슈로 연결했다. spec 요구사항 → 실패 재현 → 수정 → 독립 리뷰 →
호스트 검증 결과를 각 이슈와 [tasks](../specs/001-runtime-hardening/tasks.md)에 함께 반영한다.

Codex Security의 fix-finding 절차를 적용한다. 수정 전 읽기 전용 경계 검토와 수정 후
독립 리뷰를 수행하고, 작성자가 실제 결과를 확인한 뒤 해결 상태를 판단한다.
정적 검토나 호스트 테스트를 Android 실기기 검증으로 표시하지 않는다.

## Sentry

조직 `the-voltex-club`, 프로젝트 `buff-termux`를 읽기 전용 오류 조사에 사용한다.
2026-09-08 새 개인 토큰으로 오류 목록 API 접근을 확인했다.

설치된 Sentry 플러그인의 `skills/sentry/scripts/sentry_api.py`와
`SENTRY_AUTH_TOKEN` 환경 변수를 사용한다. 토큰에는 `event:read`, `project:read`,
`org:read` 권한이면 충분하다. [공식 권한 문서](https://docs.sentry.io/api/permissions/).
플러그인 경로는 개발 환경마다 다르므로 레포에 개인 절대 경로를 고정하지 않는다.

```powershell
# SENTRY_AUTH_TOKEN은 로컬 환경에서만 설정한다.
# SENTRY_API_SCRIPT는 설치된 플러그인의 sentry_api.py 경로이다.
python $env:SENTRY_API_SCRIPT --org the-voltex-club --project buff-termux `
  list-issues --time-range 14d --environment prod --query 'is:unresolved' --limit 20
```

환경 이름은 실제 배포 환경에 맞게 선택한다. 오류가 없다는 결과를 SDK 수집 완료로
해석하지 않는다. 런타임 SDK/DSN이나 자동 오류 전송은 이번 개발 연동에 추가하지 않았다.
Sentry 문제를 처리할 때 이슈 ID·링크·영향·재현 조건만 필요한 만큼 Linear에 기록하고,
로그인 URL, 토큰, 사용자 정보, 원본 이벤트/스택 전체를 복사하지 않는다.

로컬 `조직 토큰.txt`는 `.gitignore`로 제외한다. 자격 증명은 배포 아카이브나 테스트
복사본에 넣지 않으며, 테스트 환경에는 명시적으로 지정한 소스 파일만 복사한다.
