# Android 버전별 호환성 매트릭스

## 개요

FreeBuff Termux 호환 레이어는 Android 7.0 (Nougat) 이상에서 작동하도록 설계되었다.
이 문서는 각 Android 버전에서의 호환성 상태와 알려진 제약사항을 기록한다.

## 호환성 매트릭스

| Android 버전 | SDK | Termux | proot-distro | Bun (proot 내) | FreeBuff | 상태 |
|-------------|-----|--------|-------------|----------------|----------|------|
| 15 (Vanilla Ice Cream) | 35 | ✅ | ✅ | ✅ | ✅ | 완전 호환 |
| 14 (Upside Down Cake) | 34 | ✅ | ✅ | ✅ | ✅ | 완전 호환 |
| 13 (Tiramisu) | 33 | ✅ | ✅ | ✅ | ✅ | 완전 호환 |
| 12 (Snow Cone) | 31 | ✅ | ✅ | ✅ | ✅ | 완전 호환 |
| 11 (R) | 30 | ✅ | ✅ | ✅ | ✅ | 완전 호환 |
| 10 (Q) | 29 | ✅ | ✅ | ⚠️ | ⚠️ | 메모리 제약 |
| 9 (Pie) | 28 | ✅ | ✅ | ⚠️ | ⚠️ | 메모리 제약 |
| 8.1 (Oreo) | 27 | ✅ | ✅ | ⚠️ | ⚠️ | 메모리 제약 |
| 8.0 (Oreo) | 26 | ✅ | ⚠️ | ❌ | ❌ | proot 제약 |
| 7.1 (Nougat) | 25 | ✅ | ⚠️ | ❌ | ❌ | proot 제약 |
| 7.0 (Nougat) | 24 | ⚠️ | ❌ | ❌ | ❌ | 최소 요구 미충족 |

## 상태 범례

- ✅ 완전 호환: 모든 기능이 정상 동작
- ⚠️ 제약 있음: 동작하지만 성능/메모리 제약 존재
- ❌ 미지원: 동작하지 않음

## 버전별 상세 정보

### Android 12+ (완전 호환)

- **Termux**: 공식 지원, 모든 기능 정상 동작
- **proot-distro**: 안정적, Ubuntu/Debian distro 정상 설치
- **Bun**: proot 환경에서 정상 실행
- **FreeBuff**: 모든 기능 사용 가능
- **권장 사양**: RAM 4GB 이상, 저장공간 2GB 이상

### Android 10-11 (메모리 제약)

- **Termux**: 정상 동작
- **proot-distro**: 정상 동작하지만 메모리 부족 시 OOM Killer 종료 가능
- **Bun**: 실행 가능하지만 메모리 집약적 작업 시 위험
- **FreeBuff**: 기본 기능 동작, 대규모 코드베이스 처리 시 주의
- **권장 사양**: RAM 3GB 이상, `checkOomRisk()` 사전 실행 권장

### Android 8-9 (메모리 제약 + 성능 저하)

- **Termux**: 정상 동작
- **proot-distro**: 정상 동작하지만 성능 저하
- **Bun**: 실행 가능하지만 메모리 제약 심각
- **FreeBuff**: 제한적 사용 (소규모 프로젝트만)
- **권장 사양**: RAM 2GB 이상, `termux-wake-lock` 필수

### Android 7-8 (proot 제약)

- **Termux**: 정상 동작
- **proot-distro**: seccomp 필터 제약으로 일부 distro 설치 실패 가능
- **Bun**: proot 환경 구성 실패 시 실행 불가
- **FreeBuff**: proot 환경 구성 실패 시 사용 불가
- **해결책**: proot-distro 대신 `chroot` 또는 다른 방법 고려 필요

### Android 7.0 미만 (미지원)

- **Termux**: 구버전 APK 필요, 보안 위험
- **proot-distro**: 미지원
- 본 프로젝트는 Android 7.0 미만을 지원하지 않음

## 아키텍처별 호환성

| 아키텍처 | Termux | proot-distro | Bun | 비고 |
|----------|--------|-------------|-----|------|
| aarch64 (ARM64) | ✅ | ✅ | ✅ | 대부분의 현대 Android 기기 |
| arm (ARM32) | ✅ | ✅ | ⚠️ | 성능 저하, 구형 기기 |
| x86_64 | ✅ | ✅ | ✅ | 에뮬레이터/Chromebook |
| i386 | ✅ | ⚠️ | ❌ | 레거시, 미권장 |

## 알려진 문제와 해결책

### 1. OOM Killer에 의한 프로세스 종료 (Android 10-11)

**증상**: FreeBuff 실행 중 갑자기 종료, "Killed" 메시지
**해결책**:
```bash
# 실행 전 메모리 확인
node -e "const {checkOomRisk} = require('./dist/utils/termux-features.js'); console.log(checkOomRisk())"
# 위험 시 다른 앱 종료 후 재시도
```

### 2. Doze 모드에 의한 일시 정지 (Android 6+)

**증상**: 화면이 꺼지면 FreeBuff가 일시 정지
**해결책**:
```bash
termux-wake-lock  # 실행 전
freebuff          # FreeBuff 사용
termux-wake-unlock  # 실행 후
```

### 3. 저장소 접근 거부 (Android 11+)

**증상**: `/storage/emulated/0` 접근 시 Permission denied
**해결책**:
```bash
termux-setup-storage  # 권한 요청 다이얼로그 승인
```

### 4. proot-distro 설치 실패 (Android 7-8)

**증상**: `proot-distro install ubuntu` 실패
**해결책**: seccomp 필터 비활성화 또는 Termux F-Droid 버전 사용
