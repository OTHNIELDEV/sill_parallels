## Sill @VERSION — Mac 위의 Windows 창턱

**Apple Silicon · Intel 공용(universal) · macOS 13 이상**

### 설치
1. 아래 **`Sill-@VERSION.dmg`** 를 받아 열고, `Sill.app` 을 「Applications」로 끌어 넣습니다.
2. 처음 한 번 — Apple 개발자 서명이 없는 개인용 빌드라 macOS 가 막습니다. 한 번 열어 본 뒤
   **시스템 설정 → 개인정보 보호 및 보안 → 「그래도 열기」**, 또는 터미널에서
   ```
   xattr -dr com.apple.quarantine /Applications/Sill.app
   ```
3. 가상화 도구: `brew install qemu swtpm` (또는 앱의 「준비 상태 점검 → 필요한 도구 설치」)
4. Apple Silicon 은 **Windows 11 ARM64 ISO** 가 필요합니다(Microsoft 공식 다운로드).

### 파일
| 파일 | 용도 |
|------|------|
| `Sill-@VERSION.dmg` | 설치용 (권장) |
| `Sill-@VERSION.zip` | 같은 앱을 zip 으로 |

SHA-256:
