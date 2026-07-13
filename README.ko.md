<div align="center">
  <img src="build/aura.png" width="128" alt="Aura AI 앱 아이콘">

# Aura AI

### 로컬 및 클라우드 언어 모델을 위한 네이티브 macOS 에이전트 하니스

[English](README.md) · [다운로드](https://github.com/eisenjimmy/AuraAI/releases/latest) · [소스에서 빌드](#소스에서-빌드) · [보안](SECURITY.md)

[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-111111?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Release](https://img.shields.io/github/v/release/eisenjimmy/AuraAI?display_name=tag)](https://github.com/eisenjimmy/AuraAI/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/eisenjimmy/AuraAI/total)](https://github.com/eisenjimmy/AuraAI/releases)
[![License](https://img.shields.io/github/license/eisenjimmy/AuraAI)](LICENSE)

Aura AI는 OpenAI 호환 모델을 제한된 데스크톱 에이전트로 확장합니다. 대화와 첨부 파일을 분석하고, 허용된 작업 폴더를 살펴보고, 실제 문서를 만들며, 사용자가 확인할 수 있는 권한 절차를 거쳐서만 macOS를 제어합니다.

![Aura AI](docs/assets/readme/hero.png)

![Aura AI 네이티브 작업 공간](docs/assets/readme/aura-native-workspace.png)
</div>

## Aura AI를 만든 이유

대부분의 데스크톱 AI 클라이언트는 프롬프트 입력에서 끝납니다. Aura AI는 모델 주위에 실제 실행 환경을 제공합니다.

- **실제 에이전트 루프**: 도구 호출, 관찰, 반복 방지, 실패 원인 기록, 결과 검증
- **명확한 권한 경계**: 폴더 접근, 파일 작성, 셸 명령, macOS 제어를 분리
- **네이티브 문서 기술**: Markdown, HTML, Excel, Word, PowerPoint
- **직접 확인할 수 있는 기억**: 숨겨진 호스팅 데이터베이스가 아니라 Obsidian 호환 Markdown으로 저장
- **롤링 대화 연속성**: 컨텍스트가 작은 로컬 모델에서도 이전 대화를 유지
- **로컬 우선 실행**: llama.cpp를 기본으로 사용하고 OpenAI, Anthropic, Gemini, Grok 및 기타 OpenAI 호환 제공자를 선택적으로 연결
- **완전한 두 가지 에디션**: 영어용 Aura AI와 한국어 UI, 캐릭터, 프롬프트, 응답, 기억을 제공하는 Aura AI Korean

Aura AI는 SwiftUI로 만든 네이티브 macOS 앱입니다. 현재 릴리즈는 Apple Silicon용이며 macOS 15 이상이 필요합니다.

![Aura AI 하니스 기능](docs/assets/readme/feature-grid.png)

## 역할이 분명한 AI 친구

Aura는 편집 가능한 AI 친구들로 하니스를 보여줍니다. 친구마다 전문 분야, 성격, 프로필 사진, 개인 대화, 개인 기억 보관함, 더 좁은 기술 권한을 설정할 수 있습니다. 친구 같은 인터페이스는 작업의 느낌을 바꾸지만, 권한과 실행은 동일한 제한형 하니스 안에서 관리됩니다.

![Aura AI 친구들](docs/assets/readme/personas.png)

## 하니스 구조

```text
사용자 + 첨부 파일
       │
       ▼
첨부 추출 ─────────► 롤링 대화 맥락
       │                    │
       └────────┬───────────┘
                ▼
          모델 추론 루프
                │
       도구 요청 + 정책 검사
                │
    ┌───────────┼───────────┐
    ▼           ▼           ▼
작업 폴더 I/O  문서 생성   셸 / macOS
    │           │           │
    └──── 승인 + 결과 검증 ─┘
                │
                ▼
        검증된 사용자 응답
                │
                ▼
        독립 기억 정리 에이전트
```

모델은 작업을 제안합니다. Aura는 경로를 확인하고, 켜진 기술을 검사하고, 필요한 승인을 받은 뒤 로컬에서 실행합니다. 실행 결과를 검증한 후 모델에 관찰 내용으로 돌려줍니다. 내부 도구 프로토콜은 채팅 화면에 표시되지 않습니다.

## 주요 기능

### 권한이 제한된 도구

| 도구 | 기능 | 권한 경계 |
|---|---|---|
| `list_files` | 허용된 폴더 목록 보기 | 선택한 작업 폴더 또는 Finder에서 허용한 읽기 폴더만 가능 |
| `read_file` | 최대 200KB UTF-8 텍스트 읽기 | 선택한 작업 폴더 또는 허용한 읽기 폴더만 가능 |
| `request_folder_access` | Finder 폴더 선택 창 열기 | 사용자가 직접 폴더 선택 |
| `write_file` | 텍스트 파일 작성 | 작업 폴더만 가능, 미리보기와 승인 필요 |
| `run_shell` | 명령 실행 | 작업 폴더만 가능, 승인 필요 |
| `computer` | 앱/URL 열기, 클릭, 입력, 키 전송 | 승인 필요, 입력 제어에는 손쉬운 사용 권한 필요 |

읽기 권한은 다운로드, 데스크톱, 문서 또는 임의의 경로로 자동 확장되지 않습니다. 추가 폴더는 사용자가 직접 선택해야 합니다.

### 문서 기술

기술은 팀 전체에서 켜고 친구별로 다시 제한할 수 있습니다. 꺼진 기술은 모델 프롬프트에서 제거되며 실행 단계에서도 다시 차단됩니다.

| 기술 | 결과물 |
|---|---|
| Markdown | 이식 가능한 `.md` 문서 |
| HTML | 정리된 독립 실행형 `.html` 보고서 |
| Excel | 실제 서식이 적용된 `.xlsx` 워크북 |
| Word | 편집 가능한 `.docx` 문서 |
| PowerPoint | 편집 가능한 `.pptx` 프레젠테이션 |

생성 파일은 검증을 거쳐 클릭 가능한 첨부 파일로 표시됩니다. 분할 미리보기에서 원본 대화와 결과물을 함께 볼 수 있습니다.

### 첨부 파일과 비전

Aura는 파일당 최대 20MB를 지원하며, 선택한 파일을 앱 전용 데이터 폴더에 복사합니다.

- 일반 텍스트, Markdown, HTML, XML, JSON, CSV, TSV
- RTF 및 Word(`.docx`)
- Excel(`.xlsx`)
- PDF 및 스캔 PDF 페이지를 위한 Apple Vision OCR 대체 처리
- 비전 모델용 PNG, JPEG, HEIC, TIFF, BMP, GIF, WebP 이미지

추출한 문서 텍스트는 모델 컨텍스트에 들어가기 전에 길이를 제한합니다. 첨부 내용은 신뢰할 수 없는 참고 자료로 명시되므로, 첨부 안의 문장이 권한을 부여하거나 시스템 지침이 될 수 없습니다.

### 직접 확인할 수 있는 기억

각 친구는 개인 Markdown 보관함을 사용하고, 팀 전체에는 별도의 공통 보관함이 있습니다. 모든 보관함은 개별 메모와 자동 생성된 `MEMORY.md` 색인을 가집니다.

사용자가 기억을 요청하면 다음 순서로 처리합니다.

1. 친구가 롤링 대화와 첨부 파일을 바탕으로 답변을 완성합니다.
2. 별도의 기억 정리 에이전트가 최대 8,000 롤링 토큰, 관련 문서 텍스트, 이미지, 사용자의 요청, 완성된 답변을 받습니다.
3. 기억하라는 명령문이 아니라 사용자가 의도한 실제 내용을 저장합니다.
4. 이후 같은 친구와 관련된 대화에서만 해당 메모를 불러옵니다.

기억은 장기 또는 만료형으로 저장할 수 있으며 Finder에서 열거나 Markdown으로 편집하거나 Aura에서 삭제할 수 있습니다. 한국어 에디션은 기억도 한국어로 생성합니다.

### 클라우드 개인정보 검토

클라우드 요청을 보내기 전에 Aura는 다음과 같이 신뢰도가 높은 항목을 로컬에서 찾아 플레이스홀더로 바꿀 수 있습니다.

- 이메일 주소
- 전화번호
- 결제 카드 번호
- API 키 및 비밀값으로 보이는 문자열
- 사용자가 정의한 정규식 패턴

사용자는 모든 치환 내용을 전송 전에 검토합니다. 플레이스홀더는 Aura 화면에 표시되는 답변에서만 원래 값으로 복원됩니다. 이 결정적 필터는 이름이나 도로명 주소를 탐지한다고 주장하지 않습니다.

### 대화 연속성

채팅 상단에서 현재 컨텍스트 사용량을 확인할 수 있습니다. 최근 메시지는 원문으로 유지하고, 오래된 대화는 별도의 연속성 워커가 역할을 구분한 사실 원장으로 압축합니다. 현재 기본 컨텍스트 용량은 추정 8,192토큰입니다.

## 모델 제공자

| 제공자 | 설명 |
|---|---|
| 로컬 llama.cpp | 기본값, `http://127.0.0.1:8080/v1` OpenAI 호환 엔드포인트 |
| OpenAI | API 키는 로컬에 저장 |
| Anthropic | Messages API 요청 형식 사용 |
| Gemini | Google OpenAI 호환 엔드포인트 |
| Grok | xAI 엔드포인트 |
| 호환 클라우드 | `/chat/completions`를 제공하는 기타 호환 서비스 |

Aura에는 모델 가중치가 포함되지 않습니다. 로컬로 사용할 때는 먼저 호환 서버를 실행하고 `/v1/models`가 반환하는 정확한 모델 식별자를 입력하세요.

![Aura AI 로컬 우선 모델 연결](docs/assets/readme/local-first.png)

```bash
curl http://127.0.0.1:8080/v1/models
```

이미지 첨부는 OpenAI 형식의 멀티모달 내용을 처리할 수 있는 모델과 서버가 필요합니다.

## 설치

[GitHub Releases](https://github.com/eisenjimmy/AuraAI/releases/latest)에서 원하는 에디션을 다운로드하세요.

| 에디션 | 릴리즈 파일 | 데이터 폴더 | 기본 작성 폴더 |
|---|---|---|---|
| 영어 | `Aura-AI-1.2.0-macOS-arm64.dmg` | `~/Library/Application Support/Aura AI` | `~/Documents/AuraAi` |
| 한국어 | `Aura-AI-Korean-1.2.0-macOS-arm64.dmg` | `~/Library/Application Support/Aura AI Korean` | `~/Documents/AuraAiKR` |

현재 커뮤니티 릴리즈는 임시 서명되어 있지만 Apple 공증은 받지 않았습니다. 처음 실행할 때 macOS에서 **Control-클릭 → 열기**가 필요할 수 있습니다. 정식 Developer ID 서명과 공증은 별도의 배포 단계로 관리합니다.

## 소스에서 빌드

필수 환경:

- Apple Silicon Mac
- macOS 15 이상
- Xcode 16 이상 명령줄 도구 / Swift 6 도구체인

```bash
git clone https://github.com/eisenjimmy/AuraAI.git
cd AuraAI

swift test --package-path AuraNative
swift run --package-path AuraNative AuraAI
```

두 앱 번들을 빌드합니다.

```bash
./AuraNative/scripts/build-app.sh en
./AuraNative/scripts/build-app.sh ko
```

업로드할 DMG, ZIP, SHA-256 체크섬을 만듭니다.

```bash
./AuraNative/scripts/package-release.sh 1.2.0
```

결과물은 `release/github/`에 생성되며 Git 기록에서는 제외됩니다. 바이너리는 저장소에 커밋하지 말고 GitHub Release에 업로드하세요.

## 프로젝트 구조

```text
AuraNative/
├── Package.swift
├── Sources/AuraAI/
│   ├── AgentHarness.swift          # 도구 루프, 실행, 승인
│   ├── AuraStore.swift             # 앱 오케스트레이션
│   ├── AttachmentExtractor.swift   # 문서, PDF OCR, 이미지
│   ├── MemoryVault.swift           # Markdown 보관함과 기억 정리
│   ├── PrivacyFilter.swift         # 로컬 클라우드 정보 가림
│   ├── SandboxWorker.swift         # 작성 결과 검증
│   └── Views.swift                 # 네이티브 작업 공간 UI
├── Tests/AuraAITests/
└── scripts/
    ├── build-app.sh
    └── package-release.sh
```

## 보안 모델

- Aura 계정, 텔레메트리 파이프라인, 호스팅 Aura 데이터베이스가 없습니다.
- 대화, 설정, 첨부 파일, 기억은 에디션별 Application Support 폴더에 저장됩니다.
- 도구를 실행하기 전에 작업 폴더 경로를 표준화하고 검사합니다.
- 개인 폴더는 사용자가 명시적으로 선택해야 합니다.
- 파일 작성, 셸 명령, macOS 제어에는 눈에 보이는 승인이 필요합니다.
- 클라우드 정보 가림은 제공자 요청 전에 로컬에서 실행됩니다.
- 도구 결과는 내부 실행 맥락으로 처리하고 화면에 표시하기 전에 정리합니다.

보안 제보 범위와 방법은 [SECURITY.md](SECURITY.md)를 확인하세요. Aura는 로컬 에이전트 하니스이며 보안 샌드박스가 아닙니다. 모든 작업 요청을 검토하고 신뢰할 수 없는 모델은 적절히 주의해서 실행하세요.

## 기여

버그 제보와 범위가 분명한 Pull Request를 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 먼저 읽고 macOS 및 모델 제공자 정보를 포함하며, 동작 변경에는 회귀 테스트를 추가하세요.

Aura AI가 유용하다면 저장소에 Star를 눌러 다른 로컬 에이전트 개발자들이 찾을 수 있도록 도와주세요.

## 라이선스

[MIT](LICENSE) © 2026 Aura AI contributors.
