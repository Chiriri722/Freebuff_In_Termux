# Notes: FreeBuff Termux 프로젝트 조사 결과

## Sources

### Source 1: freebuff — npm (https://www.npmjs.com/package/freebuff)
- URL: https://www.npmjs.com/package/freebuff
- Key points:
  - 버전: 0.0.119 (3일 전 배포), 주간 다운로드 17,468
  - "The free coding agent. No subscription. No configuration."
  - Codebuff 플랫폼 기반 (Built on the Codebuff platform)
  - 오픈소스 모델 사용: DeepSeek V4 Pro, Kimi K2.6, MiniMax M3 등
  - full mode (US/캐나다/영국/EU 등) vs limited mode (그 외 지역/VPN)
  - 텍스트 광고로 수익화 (무료 운영)
  - GitHub: CodebuffAI/freebuff-private (비공개)

### Source 2: codebuff — npm (https://www.npmjs.com/package/codebuff)
- URL: https://www.npmjs.com/package/codebuff
- Key points:
  - 버전: 1.0.683, 주간 다운로드 1,090
  - 설치: npm install -g codebuff
  - Bun 기반 런타임 (shebang: #!/usr/bin/env bun)
  - HTTPS_PROXY 환경 변수 지원 (프록시/방화벽 환경)
  - codebuff.com/docs 문서, Discord 커뮤니티

### Source 3: CodebuffAI/codebuff — GitHub (https://github.com/CodebuffAI/codebuff)
- URL: https://github.com/CodebuffAI/codebuff
- Key points:
  - 7.2k stars, 880 forks, 7,310 commits
  - 언어: TypeScript 97.3%, JavaScript 2.0%
  - 디렉토리: agents/, assets/, cli/, common/, docs/, evals/, freebuff/, packages/, scripts/tmux/, sdk/
  - 빌드 도구: Bun (bun.lock, bunfig.toml, .bun-version)
  - freebuff/ 폴더: cli/ (빌드 및 npm 릴리즈), e2e/ (E2E 테스트)
  - freebuff/cli/build.ts: 기존 build-binary.ts를 FREEBUFF_MODE=true로 래핑
  - WINDOWS.md: 플랫폼별 적응 시 env var 기반 분기 패턴 사용 (CODEBUFF_GIT_BASH_PATH 등)

### Source 4: freebuff/cli/build.ts — GitHub
- URL: https://github.com/CodebuffAI/codebuff/blob/main/freebuff/cli/build.ts
- Key points:
  - #!/usr/bin/env bun (Bun 필수)
  - spawnSync('bun', ['cli/scripts/build-binary.ts', 'freebuff', version]) 호출
  - 환경 변수 FREEBUFF_MODE=true 설정 후 빌드
  - 단일 바이너리로 컴파일하여 npm 배포

### Source 5: freebuff/package.json — GitHub
- URL: https://github.com/CodebuffAI/codebuff/blob/main/freebuff/package.json
- Key points:
  - name: @codebuff/freebuff, private: true
  - 의존성 나열 없음 (빌드된 바이너리이므로)
  - 스크립트: release, build:binary, e2e:* (모두 bun 기반)

### Source 6: Bun not running in termux — GitHub Issue #5085
- URL: https://github.com/oven-sh/bun/issues/5085
- Key points:
  - "cannot execute: required file not found" 에러
  - Bun 바이너리가 Termux/Android aarch64에서 실행 불가
  - 관련 이슈: #28924 (Bun does not work on Termux)
  - 해결책: Node.js 사용 또는 proot-distro로 Linux 환경 생성

## Synthesized Findings

### FreeBuff/Codebuff 아키텍처
- FreeBuff는 Codebuff 플랫폼의 무료 변종 (FREEBUFF_MODE=true로 빌드)
- **Bun 컴파일 단일 바이너리**로 npm 배포됨
- 소스는 비공개 (freebuff-private), 빌드 스크립트만 공개
- Bun이 Termux에서 실행 불가 → 직접 설치/실행 불가

### 접근법 분석
- **A. 소스 빌드 변환**: 7,310+ 커밋 대형 코드베이스 전면 수정 → 현실적으로 불가
- **B. proot-distro 래퍼**: Termux에 Linux 환경 생성 후 Bun/FreeBuff 실행 → 가장 현실적
- **C. Node.js 바이너리 교체**: npm 패키지에서 바이너리 추출 후 Node.js 재실행 → 탐색 필요
- **추천: B + C 하이브리드** — proot를 1차, 기존 유틸리티를 경로 브리지로 활용

### 현재 프로젝트 문제점
1. tsconfig.json rootDir="./src"인데 src/ 디렉토리 없음 → 빌드 불가 (치명)
2. 실제 FreeBuff 변환 코드 부재 (환경 감지 3함수만 존재)
3. 설치 스크립트 부재
4. SKILL.md가 skill-creator 템플릿 (FB-H-I/로 이동 완료)
5. 테스트 격리 결함 (process.env.PREFIX 정리 없음)
6. .skill 내 리소스 디렉토리 전부 비어 있음
7. 가상 명령어 참조 (hermes shell exec — 실존하지 않음)
8. 입력 검증 부재 (resolvePath 경계 케이스)
9. README 부재
10. CI/CD 부재
