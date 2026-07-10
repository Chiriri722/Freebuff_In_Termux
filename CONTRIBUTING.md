# Contributing to FreeBuff in Termux

## 환영합니다!

이 프로젝트에 기여해 주셔서 감사합니다. 다음 가이드라인을 따라 주세요.

## 개발 환경 설정

```bash
# 저장소 클론
git clone https://github.com/<your-username>/Freebuff_In_Termux.git
cd Freebuff_In_Termux

# 의존성 설치
npm install

# 빌드 확인
npm run build

# 테스트 실행
npm test
```

## 개발 워크플로우

### 1. 브랜치 생성

```bash
git checkout -b feature/your-feature-name
# 또는
git checkout -b fix/issue-description
```

### 2. 코드 작성

- TypeScript strict 모드 준수
- 모든 public 함수에 JSDoc 주석 작성
- side-effect 함수와 순수 함수 분리
- 의존성 주입 패턴으로 테스트 가능성 확보

### 3. 테스트 작성

- 모든 새 기능에 대해 테스트 추가
- `tests/` 디렉토리에 `.test.ts` 파일 작성
- mock 객체를 사용한 단위 테스트 우선
- `npm test`로 모든 테스트 통과 확인

### 4. 빌드 검증

```bash
npm run build  # tsc 컴파일 오류 없음
npm test       # 모든 테스트 통과
node dist/index.js  # 런타임 확인
```

### 5. 커밋

커밋 메시지는 다음 형식을 따르세요:

```
type(scope): description

[optional body]
```

**type:**
- `feat`: 새 기능
- `fix`: 버그 수정
- `docs`: 문서 변경
- `refactor`: 리팩토링
- `test`: 테스트 추가/수정
- `chore`: 빌드, 의존성 등

**예시:**
```
feat(launcher): add interactive spawn-based FreeBuff launcher
fix(path-bridge): handle trailing slash in termux home path
docs(readme): add API reference table
```

## 아키텍처 가이드라인

### 모듈 구조

```
src/
├── types.ts          # 공유 타입 (인터페이스优先)
├── index.ts          # 공용 API (re-export only)
├── utils/            # 순수 유틸리티 (side-effect 허용)
└── proot/            # proot-distro 관련 로직
```

### 의존성 주입

테스트 가능성을 위해 외부 의존성(명령 실행, 파일 시스템 등)은
인터페이스로 추상화하고 생성자에서 주입받습니다:

```typescript
// 좋은 예: 의존성 주입
export class ProotDistroManager {
  constructor(private runner: CommandRunner = defaultCommandRunner) {}
}

// 테스트에서 mock 주입
const mgr = new ProotDistroManager(mockRunner);
```

### 경로 처리

Termux 환경의 경로는 항상 `normalizePathForTermux()`로 정규화한 후
처리합니다. 경로 변환은 `path-bridge.ts`의 순수 함수를 사용합니다.

## Termux 실기기 테스트

Windows/macOS에서 개발 후, Termux 실기기에서 검증이 필요합니다:

1. Android 기기에 Termux 설치
2. `pkg install nodejs git`
3. 저장소 클론 후 `npm install && npm run build`
4. `bash scripts/install.sh`로 proot 환경 구성
5. `freebuff` 명령으로 FreeBuff 실행 확인

## 이슈 리포트

버그 리포트나 기능 제안은 GitHub Issues에 등록해 주세요:
- 환경 정보 (Android 버전, Termux 버전, 아키텍처)
- 재현 단계
- 예상 동작 vs 실제 동작
- 에러 로그

## 라이선스

기여한 코드는 MIT 라이선스로 배포됩니다.
