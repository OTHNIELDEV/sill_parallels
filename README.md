# Sill — Mac 위의 Windows 창턱

> **Sill**(실) = 창턱(window sill). Mac 이라는 창턱 위에 Windows 창을 올려놓는다는 뜻입니다.
> 명령어 이름은 소문자 `sill` 입니다.

Parallels Desktop 처럼 Mac 위에 Windows 가상 머신을 만들고 실행하는 명령행 도구입니다.
엔진은 **QEMU + Apple Hypervisor.framework(HVF)** — CPU 는 하드웨어 가상화로 거의 원래 속도로 돕니다.

| Mac | 게스트 Windows | QEMU 머신 |
|-----|---------------|-----------|
| Apple Silicon (M1~M5) | **Windows 11 ARM64** (x64 앱은 Windows 내장 Prism 에뮬레이션으로 실행) | `virt` · HVF |
| Intel | Windows 10/11 x64 | `q35` · HVF |

> Apple Silicon 에서는 **x64 Windows 를 실행할 수 없습니다**(Parallels 도 같음). 반드시 ARM64 판 ISO 를 쓰세요.

## 내려받기

**[최신 판 받기 → Releases](https://github.com/OTHNIELDEV/sill_parallels/releases/latest)** — `Sill-<판>.dmg` (Apple Silicon · Intel 공용)

1. DMG 를 열고 `Sill.app` 을 「Applications」로 끌어 넣습니다.
2. 처음 한 번 — 개인용 빌드(Apple 개발자 서명 없음)라 macOS 가 막습니다. 한 번 열어 본 뒤
   **시스템 설정 → 개인정보 보호 및 보안 → 「그래도 열기」**, 또는 `xattr -dr com.apple.quarantine /Applications/Sill.app`
3. `brew install qemu swtpm` (또는 앱의 「준비 상태 점검」)

새 판 내기: 엔진 `sill` 의 `VERSION` 을 올려 main 에 푸시 → Actions 의 **release** 워크플로 「Run workflow」
(또는 `git tag v<판> && git push --tags`). DMG 를 직접 만들려면 `./app/scripts/build-dmg.sh [--universal]`.

## 0. 앱으로 쓰기 (SwiftUI · macOS 13 이상)

```bash
./app/scripts/build-app.sh      # → app/build/Sill.app  (Xcode 또는 Command Line Tools 필요)
open app/build/Sill.app
```

- **왼쪽** VM 목록(실행 중 표시) · **오른쪽** 시작 · 창 없이 시작 · Windows App 연결 · 종료 · 스냅숏 · 삭제
- **새 VM**(⌘N): 이름 · 설치 ISO · virtio 드라이버 · CPU · 메모리 · 디스크 · 로컬 계정
- **준비 상태 점검**: QEMU · swtpm 확인, Homebrew 설치 단추, 드라이버 받기
- **메뉴 막대 아이콘**: 창을 닫아도 VM 시작 · 연결 · 종료
- 앱은 아래 명령행 엔진 `sill` 을 묶음 안에 넣어 그대로 부릅니다 — 화면과 명령행이 같은 VM 폴더(`~/Sill`)를 공유합니다.
- 개발 중에는 `cd app && swift run` 으로도 띄울 수 있습니다.

> 지금 서명은 임시(ad-hoc)라 **빌드한 그 Mac 에서만** 바로 열립니다. 다른 Mac 에 나눠 주려면 Apple Developer ID 서명 · 공증이 필요합니다.

## 1. 준비 (한 번)

```bash
cd sill_parallels
./sill deps        # brew install qemu swtpm
./sill doctor      # ✓ 줄이 모두 나오면 준비 완료
./sill drivers     # (Apple Silicon) virtio 네트워크 드라이버 ISO → ~/Sill/virtio-win.iso
```

Windows ISO 는 Microsoft 공식 페이지에서 받습니다 — 「Download Windows 11 Disk Image (ISO) for Arm-based PCs」(Apple Silicon) / 「Download Windows 11 Disk Image (ISO)」(Intel).

## 2. VM 만들기 · 설치

```bash
./sill create win11 \
  --iso ~/Downloads/Win11_25H2_Korean_Arm64.iso \
  --virtio ~/Sill/virtio-win.iso \
  --user me            # 로컬 계정 자동 생성(Microsoft 계정 강요 없음)
./sill start win11
```

- 창이 뜨고 `Press any key to boot from CD or DVD` 가 나오면 **5초 안에 아무 키**를 누릅니다(놓치면 `sill stop win11 --force` 후 다시 시작).
- 언어 · 에디션 · 설치할 디스크만 직접 고르면 나머지는 자동입니다(`create` 가 만든 자동 설치 파일).
  - TPM 2.0 은 가상 TPM(swtpm)으로 실제 제공, Secure Boot 검사만 우회합니다.
  - 설치가 끝나면 네트워크 드라이버 · 원격 데스크톱 · 절전 끄기가 적용돼 있습니다.
- 기본값: CPU = 성능 코어 수(최대 8) · RAM 8GB · 디스크 80GB(실제로 쓴 만큼만 Mac 공간 차지).

## 3. 매일 쓰기

```bash
./sill start win11              # 창으로 실행 (창을 닫으면 VM 도 꺼짐)
./sill start win11 --background # 창 없이 실행 → 아래 rdp 로 접속
./sill rdp win11                # Microsoft 'Windows App' 으로 접속
./sill stop win11               # Windows 정상 종료 (--force = 강제)
./sill list
```

**`sill rdp` 를 권장합니다.** QEMU 기본 화면(ramfb)은 그래픽 가속이 없고 해상도가 고정이지만,
RDP 로 붙으면 Parallels 의 통합 기능 대부분을 얻습니다.

- 창 크기에 맞춰 해상도 자동 변경 · Retina 대응
- Mac ↔ Windows 클립보드 복사 · 붙여넣기
- **Mac 폴더 공유** — Windows 탐색기 「내 PC」 아래 리디렉션된 드라이브로 보임
- 소리 재생

조건: App Store 에서 **Windows App**(Microsoft) 설치 · Windows **Pro** 이상(Home 은 RDP 서버가 없음) · Windows 계정에 **암호 설정**(빈 암호는 원격 로그인이 막혀 있음).
RDP 포트는 Mac 의 `127.0.0.1` 에만 열립니다(외부에서 접근 불가).

## 4. 관리

```bash
./sill snapshot win11 save before-update   # 꺼진 상태에서 디스크 + UEFI 상태 저장
./sill snapshot win11 restore before-update
./sill snapshot win11 list
./sill set win11 ram 12                    # cpus · ram · audio · iso · virtio · rdp_port
./sill set win11 disk 120                  # 늘리기만 가능 → Windows '디스크 관리'에서 C: 확장
./sill delete win11
```

VM 은 `~/Sill/<이름>.sill/` 폴더 하나에 들어 있습니다(`disk.qcow2` · UEFI 변수 · TPM 상태 · `config.env`).
폴더째 복사하면 백업 · 이동이 됩니다(꺼진 상태에서).

## Parallels Desktop 과 비교

| 기능 | sill | 비고 |
|------|:----:|------|
| Windows 11 ARM / x64 실행 · HVF 가속 | ✅ | |
| TPM 2.0 · UEFI | ✅ | swtpm · edk2 |
| 자동 설치(계정 · 드라이버 · RDP) | ✅ | autounattend |
| 해상도 자동 · 클립보드 · 폴더 공유 · 소리 | ✅ (RDP) | 기본 창에서는 안 됨 |
| 스냅숏 | ✅ (꺼진 상태) | 실행 중 스냅숏 · 일시정지(suspend)는 미구현 |
| 3D 그래픽 가속(DirectX) | ❌ | QEMU 에 Windows 용 가속 드라이버가 없음 — 게임 · CAD 불가 |
| Coherence(Windows 앱을 Mac 창처럼) | ❌ | RDP RemoteApp 으로 일부 가능(로드맵) |
| USB 장치 연결 | ❌ | 로드맵 |
| GUI 앱 | ✅ | SwiftUI 앱 + 메뉴 막대 (0.1 — 기본 기능) |

### 왜 Apple 의 Virtualization.framework 가 아니라 QEMU 인가
Virtualization.framework 는 Linux · macOS 게스트용으로 만들어졌고, 화면 장치(virtio-gpu)에 맞는 Windows 드라이버가 없어
Windows 를 띄워도 화면이 나오지 않습니다. UTM 등 Windows 를 돌리는 무료 도구들도 같은 이유로 QEMU + HVF 를 씁니다.

## Windows 라이선스 · 주의

- Windows 사용에는 정품 라이선스가 필요합니다(설치 중 「제품 키가 없음」으로 진행 가능 · 정품 인증 전에는 개인 설정 일부 제한).
- Microsoft 가 Apple Silicon Mac 에서 「공식 지원」하는 방식은 Parallels Desktop · VMware Fusion 입니다. sill(QEMU) 으로도 실행되지만 Microsoft 지원 대상은 아닙니다.

## 검증 기록 (2026-11-22 · 엔진)

Linux 컨테이너(QEMU 8.2 · TCG 소프트웨어 에뮬레이션)에서 `test/smoke.sh` 로 확인했습니다 — 실제 Mac(HVF)에서는 아직 돌려 보지 않았습니다.

- aarch64(Apple Silicon 경로) · x86_64(Intel 경로) 모두: 생성 → 부팅(UEFI 가 NVMe 디스크 · 설치 ISO · 자동 설치 ISO 인식) → TPM 2.0 연결 → QMP 상태 → 종료 → 스냅숏 → 디스크 늘리기 통과
- 자동 설치 파일: XML 형식 검사 통과 · 아키텍처(arm64/amd64) · 드라이버 경로 치환 확인
- 실제 Windows 설치까지는 이 환경에서 하지 못했습니다(ISO 다운로드 · 실행 시간). Mac 에서 첫 설치 때 아래를 확인해 주세요:
  1. 설치 화면이 뜨는가(USB 로 붙인 ISO 부팅) 2. 설치 뒤 인터넷이 되는가(virtio 드라이버) 3. `sill rdp` 접속

Mac 에서 시험: `./test/smoke.sh` (가짜 ISO 로 1분 안에 끝남)

## 폴더 구조

```
sill                 명령행 엔진 (bash · QEMU 실행의 유일한 길)
templates/           Windows 자동 설치 응답 파일
test/smoke.sh        엔진 연기 시험
app/                 SwiftUI 앱 (Swift Package)
  Sources/SillCore   엔진 실행 · VM 목록 · 입력 검사 (Foundation 만 — Linux 에서도 시험)
  Sources/SillApp    화면 (macOS 전용)
  Tests/             단위 시험 + 실제 엔진으로 VM 만들기 · 부팅 · 종료 · 삭제
  scripts/build-app.sh  Sill.app 묶음 · build-dmg.sh DMG
.github/workflows/release.yml  범용 DMG · zip → GitHub Release
.github/workflows/   Linux(엔진) · macOS(엔진 + 앱 빌드 · 시험 · Sill.app) 자동 검사
```

## 로드맵

1. 앱 아이콘 · Developer ID 서명 · 공증 → 다른 Mac 에 배포
2. RDP RemoteApp 으로 Windows 앱 하나만 Mac 창처럼 띄우기(Coherence 대체)
3. USB 장치 연결 · 실행 중 일시정지/재개

## 라이선스

[MIT](LICENSE) © 2026 OTHNIELDEV. Sill 은 QEMU · swtpm 을 별도 프로그램으로 실행만 하며 함께 배포하지 않습니다(각자 GPL 등 자체 라이선스).
