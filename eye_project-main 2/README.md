# 👁️ AI 기반 안구 질환 통합 진단 시스템

Jetson/Raspberry Pi 기반의 엣지 AI 안구 진단 웹 애플리케이션입니다.  
실시간 카메라 스트림에서 안구를 검출하고, 질환 분류/충혈도 분석 결과를 사용자 히스토리로 저장하여 리포트 화면에서 추적합니다.

---

## 주요 기능

- 실시간 카메라 스트리밍 및 눈 감지 상태 표시 (`/video_feed`, `/detect_status`)
- 양안(좌/우) 촬영 시퀀스 기반 진단 파이프라인
- Base64 이미지 업로드 분석 API (`/analyze`)
- 사용자별 진단 히스토리 저장/조회 (`/api/history`)
- 설문(문진) 데이터 저장 (`/api/survey`)
- 분석 결과 기반 AI 가이드 생성
  - 위험도(`safe` / `warning` / `danger`)
  - 권장 진료과
  - 일상 관리 수칙
- 관리자 설정 페이지
  - `ADMIN_LOGIN_NAME` + `ADMIN_LOGIN_PASSWORD` 로그인 후 `/admin/config` 진입
  - 주요 런타임 설정을 `.env` 기반으로 조회/수정

---

## 최근 업데이트 (2026-03 기준)

- 관리자 설정 UI 추가: `web/templates/admin_config.html`
- 관리자 설정 API 추가
  - `POST /api/admin/login`
  - `GET /api/admin/config`
  - `POST /api/admin/config`
- 설문 히스토리 테이블 추가: `survey_history`
- 리포트 페이지 고도화
  - 전체 히스토리 목록
  - 이전 기록 비교
  - AI 가이드 카드(위험도/권장 진료/관리 수칙)
- 과거 데이터 마이그레이션 스크립트 추가
  - `database/backfill_guides.py`

---

## 기술 스택

- Backend: Flask, SQLite3
- AI/ML: PyTorch, torchvision, Ultralytics YOLOv8
- Vision: OpenCV, Pillow, NumPy
- Frontend: HTML/CSS/Vanilla JavaScript

---

## RPi5 Ubuntu 우선 작업 규칙

현재 장비가 Raspberry Pi 5 + Ubuntu인 경우 아래 순서를 기본으로 사용하세요.

### 1) RPi 의존성 사용

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install -r requirements_rpi.txt
```

### 2) 디바이스 기본값을 RPi로 고정

`.env` 파일에 아래 값을 유지합니다.

```bash
MODEL_DEVICE=rpi
YOLO_ONNX_PATH=models/yolo.onnx
CLASSIFIER_ONNX_PATH=models/efficientnet.onnx
```

### 3) 실행 전 프리플라이트

```bash
bash scripts/rpi_preflight.sh
```

### 3-1) ONNX 자동 변환 (필요 시)

YOLO `.pt` + 분류기 `.pth`를 RPi 실행용 ONNX로 자동 변환합니다.

```bash
bash scripts/export_onnx_rpi.sh
```

기본 출력:

- `models/yolo.onnx`
- `models/efficientnet.onnx`

### 3-2) 서비스 스크립트 구분 규칙

- 현재 로컬에서 수정한 스크립트는 RPi 전용 파일로 사용합니다.
  - `./start_services_rpi.sh`
  - `./stop_services_rpi.sh`
- RPi 스크립트의 기본 동작
  - `eye_server.py` 실행 (웹 UI 포함)
  - 브라우저 기본 URL: `http://127.0.0.1:5000/`
- RPi 키오스크 기본값은 Wayland 비활성(X11 모드)입니다.
  - 기본: `USE_WAYLAND_KIOSK=0`
  - Wayland를 강제로 쓰고 싶을 때만: `USE_WAYLAND_KIOSK=1 ./start_services_rpi.sh`
- GitHub에서 추후 내려받는 스크립트는 Jetson 전용으로 관리합니다.
  - `./start_services_jetson.sh`
  - `./stop_services_jetson.sh`
- Jetson 스크립트의 기본 동작
  - `server.py` 실행 (API 서버)
  - 헬스체크/브라우저 기준 URL: `http://127.0.0.1:5000/health`
- 기존 공용 이름(`start_services.sh`, `stop_services.sh`)은 사용하지 않습니다.

### 4) Jetson 파일 보호 훅 설치 (권장)

```bash
bash scripts/install_git_hooks.sh
```

설치 후 기본 정책:

- `inference/jetson_backend.py`
- `requirements_jetson.txt`

위 파일이 스테이징되면 커밋이 차단됩니다.
정말 의도된 Jetson 변경일 때만 아래처럼 명시적으로 우회하세요.

```bash
ALLOW_JETSON_CHANGES=1 git commit -m "..."
```

---

## 실행 방법

### 1) Python 환경 준비

```bash
python3 -m venv .venv
source .venv/bin/activate
```

### 2) 필수 패키지 설치

```bash
pip install flask opencv-python numpy pillow torch torchvision ultralytics
```

### 3) (권장) 환경변수 설정

```bash
export HASH_PEPPER='change-this-secret'
export EYE_APP_SECRET_KEY='change-this-secret-too'
```

### 4) 서버 실행

```bash
python eye_server.py
```

브라우저에서 `http://0.0.0.0:5000` 또는 장비 IP로 접속합니다.

---

## 핵심 라우트

### 페이지 라우트

- `GET /` : 메인
- `GET /login` : 사용자/관리자 로그인
- `GET /admin/config` : 관리자 설정 페이지 (세션 필요)
- `GET /capture` : 촬영
- `GET /result` : 결과
- `GET /report` : 히스토리 리포트
- `GET /survey` : 문진

### API 라우트

- `GET /status` : 서버/모델/카메라 상태
- `GET /video_feed` : MJPEG 스트림
- `GET /video_frame` : 단일 프레임 JPEG
- `GET /detect_status` : 눈 감지 상태
- `POST /analyze` : 업로드 이미지 분석 + 히스토리 저장
- `POST /diagnose` : 현재 프레임 진단
- `GET /capture/state` : 촬영 상태 조회
- `POST /capture/reset` : 촬영 상태 초기화
- `GET /api/history` : 사용자 히스토리 조회
- `POST /api/survey` : 사용자 문진 저장
- `POST /api/admin/login` : 관리자 세션 발급
- `GET /api/admin/config` : 설정 조회
- `POST /api/admin/config` : 설정 저장

---

## 데이터 저장 구조

- 진단 DB: `database/history.db`
- 이미지 저장: `web/static/captures/users/<user_id>/...jpg`
- 테이블
  - `diagnosis_history`: 분석 JSON + 이미지 경로 + 사용자 ID
  - `survey_history`: 사용자 문진 JSON

`/analyze` 호출 시 분석 결과에 `guide`가 포함되어 저장됩니다.

---

## 관리자 설정

- 로그인 화면에서 관리자 아이디/비밀번호 입력 후 로그인
- 필수 환경변수
  - `ADMIN_LOGIN_NAME` (기본 `admin`)
  - `ADMIN_LOGIN_PASSWORD` (반드시 설정)
- 설정 페이지에서 아래 주요 항목 수정 가능
  - 서버/카메라: `SERVER_IP`, `SERVER_PORT`, `CAMERA_DEVICE_INDEX`, `DEBUG_MODE`
  - 검출/분류 임계값: `YOLO_*`, `CLASSIFIER_CONFIDENCE_THRESHOLD`
  - 홍채 제거/자동촬영: `IRIS_*`, `AUTO_*`

일부 항목은 저장 후 서버 재시작 시 완전 적용됩니다.
관리자 설정 저장값은 `.env`에 기록되며, 서버 시작 시 환경변수로 반영됩니다.

---

## 백필(마이그레이션)

기존 `diagnosis_history.analysis_json`에 `guide` 필드가 없는 데이터를 보강할 수 있습니다.

```bash
# 미리보기
python database/backfill_guides.py --db database/history.db --dry-run

# 실제 반영
python database/backfill_guides.py --db database/history.db
```

---

## 현재 프로젝트 구조

실행에 직접 필요한 항목과, 운영 중 생성되는 산출물/보조 디렉터리를 함께 정리했습니다.

```text
eye_project/
├── .env
├── .env.example
├── config.py
├── config.local.json
├── eye_server.py
├── server.py
├── model_loader.py
├── README.md
├── requirements.txt
├── requirements_jetson.txt
├── requirements_rpi.txt
├── start_services.sh
├── stop_services.sh
├── PHOTO/
├── eye_photo/
├── docs/
│   └── RPI5_UBUNTU_RUNBOOK.md
├── scripts/
│   ├── export_onnx_rpi.sh
│   ├── install_git_hooks.sh
│   └── rpi_preflight.sh
├── database/
│   ├── app.py
│   ├── appopen.py
│   ├── backfill_guides.py
│   ├── db.py
│   └── schema.sql
├── inference/
├── logs/
├── models/
│   └── Augmented_EffNet_V1_B0_best.pth
├── modules/
│   ├── __init__.py
│   ├── analyzer.py
│   ├── classifier.py
│   └── detector.py
├── utils/
│   ├── image_proc.py
│   ├── logger.py
│   └── security_utils.py
└── web/
    ├── static/
    │   ├── captures/
    │   ├── images/
    │   ├── reports/
    │   ├── css/
    │   │   └── chat-widget.css
    │   └── js/
    │       └── chat-widget.js
    └── templates/
        ├── admin_config.html
        ├── capture.html
        ├── index.html
        ├── login.html
        ├── m_dashboard.html
        ├── m_login.html
        ├── report.html
        ├── result.html
        └── survey.html
```

---

## 참고

- 본 시스템은 의료 진단 보조 목적의 스크리닝 도구이며, 최종 의학적 판단은 전문의 진료를 통해 확정되어야 합니다.