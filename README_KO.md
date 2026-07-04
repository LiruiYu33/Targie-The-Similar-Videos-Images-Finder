# <img src="asset/icon_white.png" width="28" alt="" /> Targie

[English](README.md) | [简体中文](README_ZH.md) | [繁體中文](README_ZH_HANT.md) | [Español](README_ES.md) | [Français](README_FR.md) | [日本語](README_JA.md)

> **macOS 전용입니다.** Targie는 macOS 14+용 네이티브 앱입니다. Windows 또는 Linux 빌드는 없으며, 제공할 계획도 없습니다.

Targie는 메타데이터, 콘텐츠 해시, 지각 지문, 시각 특징을 결합해 선택한 폴더 안의 유사한 동영상과 이미지를 찾습니다.

## 기능

- 동영상, 이미지, 전체 스캔 모드를 전환할 수 있고 선택한 모드를 기억합니다.
- 폴더 선택기나 Finder 드래그 앤 드롭으로 여러 폴더를 추가한 뒤, 선택한 모든 폴더의 미디어를 함께 비교합니다.
- 일반적인 동영상 형식과 JPEG, PNG, HEIC, HEIF, WebP, TIFF, GIF, BMP 이미지를 재귀적으로 스캔합니다.
- SHA-256, 캐시된 지각 지문, 메타데이터, 재사용 가능한 Vision 특징을 사용하며, 읽을 수 없는 파일은 분리해 처리합니다.
- 동영상과 이미지 그룹을 분리해 앱 안의 정적 미리보기로 나란히 검토할 수 있습니다.
- 동영상을 기본 플레이어로 열고, 모든 미디어 파일을 Finder에서 표시할 수 있습니다.
- 명시적인 다중 선택과 부분 성공을 처리하는 일괄 삭제를 지원합니다.
- 삭제할 때 휴지통으로 이동할지 영구 삭제할지 반드시 선택해야 하며, 영구 삭제는 한 번 더 확인합니다.
- 영어, 중국어 간체, 중국어 번체, 스페인어, 프랑스어, 일본어, 한국어를 즉시 전환할 수 있고 선택한 언어를 기억합니다.
- **찾아보기 모드**: 선택한 폴더의 모든 파일을 정렬 및 필터링 가능한 표로 볼 수 있습니다. 열 너비 드래그 조절, 일괄 선택, 필터링된 파일 수를 반영하는 실시간 창 제목을 지원합니다.

![이미지 유사도 비교](asset/Screenshot1.png)

![동영상 유사도 비교](asset/Screenshot2.png)

![찾아보기 모드 — 파일 목록과 미리보기](asset/Screenshot3.png)

## 설치

1. [Releases](https://github.com/LiruiYu33/Targie-The-Similar-Videos-Images-Finder/releases)에서 최신 `Targie-v*.zip`을 다운로드합니다.
2. zip 압축을 풀고 **Targie.app**을 응용 프로그램 폴더나 원하는 위치로 드래그합니다.
3. 이 앱은 ad-hoc 서명되어 있습니다. 처음 실행할 때 macOS Gatekeeper가 차단합니다.
   - 앱을 **오른쪽 클릭**(또는 Control-클릭) → **열기** → 대화상자에서 **열기**를 클릭합니다.
   - 또는 **시스템 설정 → 개인정보 보호 및 보안**으로 이동해 맨 아래까지 스크롤한 뒤, Targie 항목 옆의 **그래도 허용**을 클릭하고 앱을 정상적으로 엽니다.
   - 이 작업은 한 번만 필요합니다. 첫 실행에 성공하면 Gatekeeper가 다시 차단하지 않습니다.

## 빌드(macOS 전용)

```bash
swift test
./script/build_app.sh
```

생성된 앱은 다음 위치에 있습니다.

```text
dist/Targie.app
```

개발 중에는 다음 명령으로 빌드하고 실행할 수 있습니다.

```bash
./script/build_and_run.sh
```

앱은 로컬 사용을 위해 ad-hoc 서명되어 있습니다. 인터넷이나 App Store를 통한 배포에는 Developer ID, 공증, 적절한 패키징 절차가 필요합니다.

## 라이선스

Targie는 **[GNU General Public License v3.0](LICENSE)** 라이선스를 따릅니다.

Copyright (C) 2026 Lirui Yu.

이 코드를 재사용하는 경우(수정 여부와 관계없이):

- 저작권 고지를 유지하고 원저자(Lirui Yu)를 명시해야 **합니다**.
- 배포하는 파생 저작물은 GPL-3.0(또는 이후 GPL 버전)으로도 공개해야 하며, 사용자에게 전체 소스 코드를 제공해야 **합니다**.
- 폐쇄 소스 또는 독점 재배포는 **허용되지 않습니다**.

전체 법적 문구는 [LICENSE](LICENSE) 파일을 참조하세요.

## 기여

Pull Request를 환영합니다. 모든 commit은 [Developer Certificate of Origin (DCO)](DCO)에 따라 sign-off 되어야 합니다. `git commit`에 `-s`를 추가하세요. 자세한 내용은 [CONTRIBUTING.md](CONTRIBUTING.md)를 참조하세요.
