<div align="center">

# 아우라 AI

**개성, 기억, 이미지 채팅, 로컬 LLM, 네이티브 macOS 클라이언트를 갖춘 프라이빗 AI 팀입니다.**

**언어:** [English](README.md) · 한국어

[![Electron](https://img.shields.io/badge/Electron-33-2b2e3a?logo=electron)](https://www.electronjs.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-native%20macOS-f05138?logo=swift)](AuraNative/)
[![React](https://img.shields.io/badge/React-18-087ea4?logo=react)](https://react.dev/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178c6?logo=typescript)](https://www.typescriptlang.org/)
[![Local-first](https://img.shields.io/badge/local--first-yes-3fb950)](#프라이버시와-로컬-파일)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

![Aura AI hero banner](docs/assets/readme/hero.png)

**일곱 명의 AI 캐릭터와 대화하고, 기억은 내 컴퓨터의 파일로 보관하고, 이미지를 첨부하고, 필요하면 로컬 모델로 실행하세요.**

**네이티브 macOS:** `AuraNative/`는 Aura의 SwiftUI macOS 클라이언트입니다. macOS에서는 브라우저 셸을 대체하는 방향으로 개발하며, 기존 Electron 앱은 마이그레이션 기간 동안 Windows 릴리즈 경로로 유지됩니다.

[빠른 시작](#빠른-시작) · [영어한국어 에디션](#영어한국어-에디션) · [캐릭터 소개](#캐릭터-소개) · [이미지 채팅](#이미지-채팅) · [로컬 LLM 설정](#로컬-llm-설정) · [코드 에이전트 핸드오프](#코드-에이전트-핸드오프)

</div>

---

## 아우라 AI란?

아우라 AI는 명령줄 같은 AI가 아니라, 내 컴퓨터 안에 있는 작은 친구 그룹처럼 느껴지는 데스크톱 채팅 앱입니다.

- **일곱 명의 기본 캐릭터**가 서로 다른 말투, 목소리, 프로필 이미지를 가집니다.
- **이미지 채팅**으로 스크린샷, 디자인, 사진, 문서 이미지를 함께 보낼 수 있습니다.
- **내 프로필 사진 업로드**를 온보딩과 설정에서 지원하고, 내 메시지 옆에 표시합니다.
- **캐릭터별 기억**으로 각 캐릭터가 나와 나눈 대화에서 배운 것만 기억합니다.
- **공통 기억**으로 모든 캐릭터가 공유할 수동 기억을 따로 관리합니다.
- **Kokoro TTS**로 캐릭터별 음성 답변을 들을 수 있습니다.
- **초보자용 로컬 LLM 설정**으로 앱 안에서 모델 다운로드와 llama.cpp 실행을 도와줍니다.
- **OpenAI, Anthropic, Gemini**도 선택적으로 연결할 수 있습니다.
- **계정, 텔레메트리, 호스팅 데이터베이스가 없습니다.**

![Aura local-first visual](docs/assets/readme/local-first.png)

![Aura feature overview](docs/assets/readme/feature-grid.png)

## 빠른 시작

### 방법 1: 릴리즈 다운로드

GitHub Releases에서 원하는 에디션을 받으세요.

- macOS: `.dmg`, `.zip`
- Windows: NSIS `.exe`

### 방법 2: 소스에서 실행

```bash
git clone https://github.com/eisenjimmy/AuraAI.git
cd AuraAI
npm install
npm run dev
```

한국어 빌드로 개발 실행을 확인하려면:

```bash
npm run build:ko
npm run start
```

## 영어/한국어 에디션

한 GitHub 저장소에서 두 데스크톱 에디션을 빌드합니다.

| 에디션 | 앱 이름 | 화면 언어 | 기본 캐릭터 | 기본 데이터 폴더 |
|---|---|---|---|---|
| English | Aura AI | 영어 | Nova, Sage, Rio, Luna, Max, Gilleon, Neir | Aura AI |
| Korean | Aura AI Korean / 아우라 AI | 한국어 | 하나, 서윤, 재민, 은별, 민준, 길온, 나이르 | Aura AI Korean |

빌드 명령:

```bash
npm run dist:en:mac
npm run dist:en:win
npm run dist:ko:mac
npm run dist:ko:win
```

아무 플래그도 주지 않으면 영어 에디션이 기본입니다.

## 캐릭터 소개

![Aura personas banner](docs/assets/readme/personas.png)

한국어 에디션은 한국어 이름, 한국어 시스템 프롬프트, 한국인 느낌의 기본 프로필 이미지를 사용합니다. 한국에 익숙한 예능, 동네 장사, 스타트업, 제품 발표 문화 같은 정서를 패러디하되, 특정 실존 인물의 이름이나 외모를 그대로 쓰지는 않습니다.

| 캐릭터 | 프로필 | 성격 |
|---|---:|---|
| **하나** | <img src="src/renderer/src/assets/avatars/nova-ko.png" width="88" alt="하나 프로필"> | 햇살 같은 리액션과 따뜻한 장난기가 있는 친구. |
| **서윤** | <img src="src/renderer/src/assets/avatars/sage-ko.png" width="88" alt="서윤 프로필"> | 전직 교사 같은 차분함, 좋은 질문, 판단 없는 시선. |
| **재민** | <img src="src/renderer/src/assets/avatars/rio-ko.png" width="88" alt="재민 프로필"> | 한국식 티키타카와 드립, 그래도 답은 실용적으로. |
| **은별** | <img src="src/renderer/src/assets/avatars/luna-ko.png" width="88" alt="은별 프로필"> | 홍대 작업실과 새벽 감성에 어울리는 조용한 공감. |
| **민준** | <img src="src/renderer/src/assets/avatars/max-ko.png" width="88" alt="민준 프로필"> | 동네 가게 사장님 같은 현실감, 직설, 의리. |
| **길온** | <img src="src/renderer/src/assets/avatars/gilleon-ko.png" width="88" alt="길온 프로필"> | 발명가형 창업자 패러디. 빠르고 날카롭고 기술적입니다. |
| **나이르** | <img src="src/renderer/src/assets/avatars/neir-ko.png" width="88" alt="나이르 프로필"> | 흰 머리의 미니멀리스트 디자이너이자 제품 비전가. |

각 캐릭터는 이름, 한 줄 소개, 시스템 프롬프트, 포인트 색상, Kokoro 목소리, 프로필 이미지를 바꿀 수 있습니다. 기본 프로필 이미지는 언제든 복원할 수 있고, 사용자가 직접 이미지를 업로드할 수도 있습니다.

프로필 이미지는 설정에서 바꿀 수 있습니다. 아우라는 일곱 개의 기본 생성 프로필, 한국인/유럽계/흑인/라틴계/남아시아/중동계/은발/혼혈 스타일을 포함한 열 개의 추가 선택지, 그리고 사용자 업로드를 제공합니다.

## 이미지 채팅

채팅 입력창의 이미지 버튼으로 이미지를 첨부하세요. 아우라는 이미지를 설정된 폴더로 복사하고, 채팅에 썸네일로 보여주며, vision을 지원하는 모델에는 현재 첨부 이미지를 함께 보냅니다.

한국어 에디션의 기본 저장 위치:

```text
Documents/AuraAiKR
```

설정에서 변경할 수 있습니다:

```text
설정 -> 채팅 및 기능 -> 이미지 업로드 폴더
```

## 로컬 LLM 설정

초보자용 설정은 추천 GGUF 모델을 다운로드하고, 아우라 설정에 연결하고, 앱 안에서 llama.cpp 서버를 실행할 수 있게 도와줍니다. 고급 사용자는 이 흐름을 건너뛰고 Ollama, LM Studio, 기존 llama.cpp 서버 또는 클라우드 제공자를 직접 설정할 수 있습니다.

추천 초보자 설정은 다음과 같습니다.

| 설정 | 기본값 |
|---|---|
| 제공자 | Local llama.cpp |
| URL | `http://127.0.0.1:8080/v1` |
| 모델 | Gemma 4 E4B / `gemma4-v2` |

이 저장소에는 이 컴퓨터에서 쓰는 Jarvis Gemma 4 v2 llama.cpp 런타임 실행 스크립트가 포함되어 있습니다.

```bash
npm run llm:gemma4-v2
```

그다음 아우라에서 **로컬 (llama.cpp)** 를 선택하세요.

## 프라이버시와 로컬 파일

아우라는 데이터를 숨겨진 서버가 아니라 내 컴퓨터의 일반 파일로 보관합니다.

| 데이터 | 위치 |
|---|---|
| 설정과 API 키 | 앱 설정 JSON |
| 내 프로필 사진 | 앱 데이터 `avatars/` 폴더 |
| 캐릭터 수정 | `personas.json` |
| 채팅 | `chats/<persona>.json` |
| 기억 | 마크다운 기억 보관함 |
| 업로드한 프로필 이미지 | 앱 데이터 `avatars/` 폴더 |
| 업로드한 채팅 이미지 | 기본 `Documents/AuraAiKR`, 설정 가능 |

네트워크 트래픽은 선택한 AI 제공자와, 웹 검색이 켜져 있을 때 선택한 검색 제공자로만 나갑니다.

## 네이티브 macOS 클라이언트

`AuraNative/`는 Aura를 브라우저 래퍼가 아닌, 경계가 분명한 작은 AI 팀으로 쓰고 싶은 사용자를 위한 SwiftUI macOS 앱입니다. 온보딩에서 모델 연결을 선택하고, 클라우드 프라이버시 검토를 설정한 뒤, 첫 팀 역할을 고릅니다.

- 기존 Aura 친구가 중심입니다. **하나**(비서실장), **서윤**(피플/HR), **재민**(개발), **은별**(리서치), **민준**(IT), **길온**(제품 전략), **나이르**(디자인과 비전)를 그대로 만날 수 있습니다. **유진**은 법률 및 리스크 관점을 더합니다. 각 친구는 대화, 프로필 이미지, 캐릭터 기억을 분리해서 가집니다.
- 팀 전체가 공유하는 공통 기억을 직접 편집할 수 있습니다.
- 클라우드 요청 전 네이티브 프라이버시 검토를 제공합니다. 이메일, 전화번호, 카드번호, API 비밀값으로 보이는 항목을 로컬에서 플레이스홀더로 바꾸고, 전송 전에 사용자가 확인합니다. 응답은 Aura 화면에서만 다시 복원됩니다.
- 워크스페이스와 데스크톱 작업을 위한 제한된 에이전트 하니스를 제공합니다. 선택한 워크스페이스 안의 읽기는 자동이지만, 다운로드 폴더 같은 개인 폴더는 Finder에서 명시적으로 허용해야 합니다. 파일 쓰기, 셸 명령, macOS 제어는 매번 한 번씩 승인이 필요합니다. 클릭과 타이핑에는 macOS 손쉬운 사용 권한도 필요합니다.
- 하나의 채팅 입력창에서 텍스트와 여러 첨부 파일을 함께 보낼 수 있습니다. 파일당 최대 **20MB**까지 지원하며, 선택한 파일은 Aura의 전용 앱 데이터에 복사됩니다. Word(`.docx`), Excel(`.xlsx`), PDF, 이미지, Markdown, HTML, CSV, 텍스트 내용을 추출해 대화 맥락으로 유지하고, 작은 로컬 모델의 컨텍스트를 넘지 않도록 추출 텍스트 예산을 제한합니다.
- 이미지와 스캔 PDF의 OCR은 macOS의 Apple Vision 프레임워크로 오프라인 실행됩니다. 모델 다운로드, Python 서비스, 클라우드 요청이 필요하지 않습니다. 실험적인 `baidu/Unlimited-OCR`은 공식 배포가 커스텀 Python/CUDA 추론과 수 GB 모델을 요구하므로 앱에 직접 포함하지 않았으며, 향후 선택형 외부 엔드포인트로 연결할 수 있습니다.
- 도구 사용을 허용한 친구는 선택한 작업 폴더 안에 실제 `.xlsx` 워크북, 독립 실행형 HTML 보고서, Markdown 문서를 만들 수 있습니다. 파일을 쓰기 전에는 항상 미리보기와 승인을 요청합니다.
- 생성한 문서는 친구의 답변 아래 클릭 가능한 파일 첨부로 표시됩니다. Aura는 문서에 적힌 표준 도구 호출 JSON과 일부 로컬 모델이 출력하는 평면 JSON 형식을 모두 처리하며, 닫는 도구 태그가 빠진 복구 가능한 응답도 처리합니다.

도구 사용 스위치는 **설정 > 도구**에만 있습니다. 채팅 화면에는 반복해서 표시하지 않습니다.

설정 창은 720 x 600 크기로 고정되어 탭을 바꿔도 크기가 변하거나 다시 중앙으로 이동하지 않습니다. 설정과 친구 추가 창에는 명시적인 닫기 버튼이 있습니다.

사이드바에서 친구를 우클릭하고 **친구 편집**을 선택하면 네이티브 편집 창이 열립니다. 기본 프로필 사진 16개 중 하나로 되돌리거나 직접 사진을 업로드할 수 있고, 이름, 전문 분야, 한 줄 소개, 성격 지침을 설정할 수 있습니다. 같은 우클릭 메뉴에서 **기억 열기**도 사용할 수 있습니다.

한국어 에디션은 기존 Electron 앱에서 검증한 한국어 캐릭터 프롬프트를 그대로 사용합니다. 사용자가 다른 언어를 명시적으로 요청하지 않는 한, 일반 대화와 도구 작업 모두 자연스러운 한국어로 답합니다.

초기 네이티브 프라이버시 레이어는 의도적으로 보수적입니다. 별도로 검증된 온디바이스 분류기가 배포되기 전에는 이름이나 도로명 주소를 분류한다고 주장하지 않습니다.

네이티브 온보딩의 기본 모델은 로컬 llama.cpp 엔드포인트의 **Gemma 4 E4B Instruct** (`gemma-4-E4B-it-Q4_K_M`)입니다. 설정 과정에서 다른 로컬 또는 클라우드 모델을 선택할 수 있습니다.

```bash
swift run --package-path AuraNative AuraAI
./AuraNative/scripts/build-app.sh en
./AuraNative/scripts/build-app.sh ko
```

번들 스크립트는 `build/AuraMale2.png`를 macOS 아이콘으로 패키징하고, ad-hoc 서명된 로컬 `.app`을 `release/`에 만듭니다.

## 기억

기억은 두 층으로 나뉩니다.

- **공통 기억**은 모든 캐릭터가 공유하는 수동 기억입니다. 사이드바의 설정 위에서 열 수 있습니다.
- **캐릭터별 기억**은 각 캐릭터와 나눈 대화에서 배운 내용만 담습니다. A 캐릭터에게 말한 내용이 B 캐릭터에게 자동으로 공유되지 않습니다.

캐릭터별 기억은 채팅 상단 프로필 이미지, 대화 속 캐릭터 아바타, 또는 친구 목록의 프로필 이미지를 우클릭해서 열 수 있습니다.

## 음성

아우라는 로컬 음성 합성에 [Kokoro TTS](https://github.com/hexgrad/kokoro)를 사용합니다.

각 캐릭터는 Kokoro 목소리와 말하기 속도를 가집니다. 첫 재생 때 모델 파일을 불러오므로 첫 음성 답변은 조금 더 오래 걸릴 수 있습니다.

Kokoro 모델 파일과 지원되는 음성 바이너리는 앱에 함께 포함되어 있으며, 아우라의 내부 `aura-kokoro://` 에셋 서비스로 불러옵니다. 음성 미리듣기와 음성 답변은 첫 실행 시 Hugging Face 다운로드가 필요하지 않습니다. 음성 답변이 켜져 있으면 앱 시작 시, 그리고 설정에서 처음 켤 때 로컬 Kokoro 런타임을 미리 준비합니다.

## 릴리즈 빌드

```bash
npm run typecheck
npm run dist:en:mac
npm run dist:en:win
npm run dist:ko:mac
npm run dist:ko:win
```

생성된 설치 파일은 `release/` 폴더에 들어갑니다.

## 코드 에이전트 핸드오프

```text
AuraAI Electron + React + TypeScript 저장소에서 작업한다.

목표:
영어 에디션과 한국어 에디션을 모두 유지하면서 로컬 llama.cpp 제공자, 이미지 업로드, 기억, Kokoro 음성 설정을 검증한다.

중요:
- 영어 에디션은 기본값이므로 AURA_EDITION 플래그 없이 빌드한다.
- 한국어 에디션은 AURA_EDITION=ko 또는 npm run build:ko/dist:ko:*로 빌드한다.
- 기본 로컬 제공자:
  - baseUrl: http://127.0.0.1:8080/v1
  - model: gemma4-v2
- 로컬 모델 실행:
  npm run llm:gemma4-v2
- 검증:
  npm run typecheck
  npm run build
  npm run build:ko
- 이미지 첨부 중에도 텍스트 입력이 가능한지 확인한다.
- 한국어 IME 입력을 보낸 뒤 마지막 글자가 입력창에 남지 않는지 확인한다.
- 사이드바에서 공통 기억을 연다.
- 캐릭터 프로필 이미지를 클릭하거나 우클릭해서 캐릭터별 기억을 연다.
- Kokoro 음성에서 fetch 오류가 나면 네트워크를 확인한 뒤 앱 재시작 없이 다시 시도한다.
- 파괴적인 git 명령을 실행하지 않는다.
```

## 라이선스

MIT. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.
