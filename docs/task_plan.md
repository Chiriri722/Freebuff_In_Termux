# Task Plan: FreeBuff Termux 프로젝트 구조 구축

## Goal
FreeBuff Termux 변환 레이어의 프로젝트 구조를 표준화하여 빌드가 정상 동작하는 기반을 마련하고, B+C 전략(proot-distro + Node.js) 구현을 위한 밑작업을 완료한다.

## Phases
- [x] Phase 1: planning-with-files 문서 생성 (task_plan.md, notes.md, PLAN.md)
- [x] Phase 2: 소스 코드 src/ 구조로 이동 및 import 경로 수정
- [x] Phase 3: 설정 파일 수정 (tsconfig.json, package.json, .gitignore, jest.config.cjs)
- [x] Phase 4: 빌드 검증 (tsc 컴파일 + node dist/index.js + jest 9/9 passed)

## Key Questions
1. tsconfig.json의 rootDir/include 경로를 src/에 맞게 수정했는가?
2. 모든 import 경로가 새 디렉토리 구조에 맞게 변경되었는가?
3. npx tsc가 오류 없이 컴파일을 완료하는가?
4. 컴파일된 dist/index.js가 정상 실행되는가?

## Decisions Made
- 프로젝트 구조: src/ (소스) + tests/ (테스트) + docs/ (문서) 분리
- 소스 파일은 src/utils/ 하위에 배치 (termux-utils.ts, path-utils.ts)
- 테스트 파일은 tests/ 하위에 배치, src/에서 분리
- 접근법 B+C 채택: proot-distro를 1차 메커니즘, Node.js 바이너리 교체를 2차 전략
- 축 1(구조 구축)까지만 현재 세션에서 실행, 이후 새 레포지터리로 이관

## Errors Encountered
- [npm install 타임아웃] npm install이 30초 타임아웃으로 중단 → node_modules 불완전 설치 → node_modules 삭제 후 `npm install --prefer-offline`로 해결
- [npx tsc 잘못된 패키지] `npx tsc`가 `tsc@2.0.4`(별도 패키지) 참조 → `node node_modules/typescript/bin/tsc` 직접 실행으로 해결
- [jest.config.js 정규식 손상] 편집기에서 정규식 백슬래시 이스케이프 손상 → CommonJS 임시 스크립트로 파일 작성으로 해결
- [ESM에서 ts-jest 미해석] `export default` (ESM) 설정으로 ts-jest(CommonJS) 해석 실패 → `jest.config.cjs`(CommonJS)로 전환하여 해결
- [bs-logger 모듈 누락] 불완전 설치로 `./logger` 모듈 없음 → node_modules 완전 삭제 후 재설치로 해결
- [이중 슬래시 버그] resolvePath에서 prefix + path 결합 시 `/usr//etc/config` 발생 → path가 `/`로 시작하므로 prefix 끝 슬래시 여부에 따라 분기 처리
- [ESM 실행 가드 Windows 미지원] `import.meta.url === file://...` 비교가 Windows 경로에서 실패 → `fileURLToPath(import.meta.url) === process.argv[1]`로 해결
- [ts-jest TS151002 경고] hybrid module kind에 `isolatedModules: true` 필요 → tsconfig.json에 추가하여 해결

## Status
**Phase 4 완료 — 구조 구축 완료** — 모든 빌드 및 테스트 검증 통과
