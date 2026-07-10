# 아키텍처: FreeBuff Termux 호환 레이어

## 기술 결정 배경

### 문제 정의

FreeBuff는 Codebuff 플랫폼 기반의 무료 AI 코딩 에이전트입니다:
- npm 패키지 `freebuff` (v0.0.119)로 배포
- **Bun 런타임**으로 컴파일된 단일 바이너리 (`#!/usr/bin/env bun`)
- 소스 코드는 비공개 (`CodebuffAI/freebuff-private`)

Bun은 Termux/Android aarch64에서 **실행 불가**합니다:
- `cannot execute: required file not found` 에러
- Bun 바이너리가 Android의 실행 파일 포맷을 지원하지 않음
- 관련 이슈: [oven-sh/bun#5085](https://github.com/oven-sh/bun/issues/5085), [#28924](https://github.com/oven-sh/bun/issues/28924)

### 접근법 비교

| 접근법 | 설명 | 결론 |
|--------|------|------|
| A. 소스 빌드 변환 | Codebuff 소스를 클론하여 Bun API를 Node.js로 변환 | 7,310+ 커밋 대형 코드베이스 → **불가** |
| **B. proot-distro 래퍼** | Termux에 Linux 환경 생성 후 Bun 실행 | **채택** (1차 메커니즘) |
| **C. Node.js 바이너리 교체** | npm 패키지에서 바이너리 추출 후 Node.js 재실행 | **탐색** (2차 전략) |

## 시스템 아키텍처

```
┌─────────────────────────────────────────────────┐
│                   Termux (Android)               │
│                                                   │
│  ┌─────────────┐    ┌──────────────────────────┐ │
│  │  Wrapper     │    │  proot-distro             │ │
│  │  ~/.local/   │───▶│  ┌─────────────────────┐ │ │
│  │  bin/        │    │  │  Ubuntu (rootfs)     │ │ │
│  │  freebuff    │    │  │  ┌─────────────────┐ │ │ │
│  └─────────────┘    │  │  │  Bun runtime     │ │ │ │
│       │              │  │  │  ┌───────────┐  │ │ │ │
│       ▼              │  │  │  │  freebuff  │  │ │ │ │
│  ┌─────────────┐    │  │  │  │  CLI binary │  │ │ │ │
│  │ Path Bridge  │    │  │  │  └───────────┘  │ │ │ │
│  │ (termux ↔    │    │  │  └─────────────────┘ │ │ │ │
│  │  proot 변환)  │    │  └─────────────────────┘ │ │ │
│  └─────────────┘    └──────────────────────────┘ │
│       │                       │                   │
│       ▼                       ▼                   │
│  /data/data/com.termux/   /storage/emulated/0     │
│  files/home/              (bind mount)             │
└─────────────────────────────────────────────────┘
```

## 컴포넌트 설명

### 1. termux-utils.ts — 환경 감지
- `isTermux()`: `PREFIX` 환경 변수로 Termux 감지
- `getTermuxPrefix()`: `/data/data/com.termux/files/usr` 반환

### 2. path-utils.ts — 경로 보정
- `resolvePath()`: 시스템 절대 경로를 Termux PREFIX 기반으로 변환
- 예: `/etc/config` → `/data/data/com.termux/files/usr/etc/config`

### 3. system-utils.ts — 시스템 정보
- `getArch()`: CPU 아키텍처 감지 (aarch64, arm, x86_64)
- `getAndroidVersion()`: Android 버전 조회
- `isCommandAvailable()`: 명령어 존재 확인 (크로스 플랫폼)
- `normalizePathForTermux()`: 경로 정규화 (`.`, `..`, `~`, 중복 슬래시)

### 4. path-bridge.ts — Termux ↔ proot 경로 변환
- `termuxToProot()`: Termux 홈 하위 경로 → proot 홈 하위 경로
- `prootToTermux()`: 역방향 변환
- 공유 저장소(`/storage/emulated/0`)는 bind mount로 그대로 유지

### 5. proot-wrapper.ts — proot-distro 관리
- `ProotDistroManager` 클래스
- `CommandRunner` 인터페이스 주입으로 테스트 가능
- distro 설치, Bun/FreeBuff 설치, FreeBuff 실행, 사전 검증

### 6. install.sh — 설치 자동화
- Termux 의존성 설치 → proot-distro Ubuntu 설치
- distro 내부에 Bun + FreeBuff 설치
- 래퍼 스크립트 생성 및 PATH 등록

## 데이터 흐름

```
사용자: cd ~/my-project && freebuff
  │
  ▼
Wrapper 스크립트 (~/.local/bin/freebuff)
  │  1. 현재 디렉토리 감지: /data/data/com.termux/files/home/my-project
  │  2. 경로 변환: /root/my-project (proot 홈)
  │
  ▼
proot-distro login ubuntu --bind /storage/emulated/0
  │  3. Ubuntu 환경 진입
  │  4. Bun 환경 변수 로드
  │  5. cd /root/my-project
  │
  ▼
freebuff (Bun 바이너리)
  │  6. AI 코딩 에이전트 실행
  │  7. 파일 읽기/쓰기 (proot 홈 경로 사용)
  │
  ▼
파일 시스템 (proot rootfs)
  │  8. /root/my-project/* → 실제로는 Termux 파일 시스템에 저장
  │  9. /storage/emulated/0/* → Android 공유 저장소 (bind mount)
```
