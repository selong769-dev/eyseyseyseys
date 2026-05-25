"""
[설정] 눈병 진단 시스템 중앙 관리
- IP주소, 모델 경로, 임계값, 클래스명
"""

import os
import torch


def _get_env_str(name, default):
    value = os.getenv(name)
    if value is None:
        return default
    value = str(value).strip()
    return value if value != '' else default


def _get_env_int(name, default):
    value = os.getenv(name)
    if value is None or str(value).strip() == '':
        return int(default)
    try:
        return int(str(value).strip())
    except Exception:
        return int(default)


def _get_env_float(name, default):
    value = os.getenv(name)
    if value is None or str(value).strip() == '':
        return float(default)
    try:
        return float(str(value).strip())
    except Exception:
        return float(default)


def _get_env_bool(name, default):
    value = os.getenv(name)
    if value is None:
        return bool(default)

    text = str(value).strip().lower()
    if text in ('1', 'true', 'yes', 'y', 'on'):
        return True
    if text in ('0', 'false', 'no', 'n', 'off'):
        return False
    return bool(default)

# ========================================
# [1] 기본 경로 설정
# ========================================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_DIR = os.path.join(BASE_DIR, 'models')

# ========================================
# [1-1] Device 설정 (CPU 우선, Jetson Orin Nano 메모리 절약)
# ========================================
DEVICE = torch.device('cpu')  # Jetson Orin Nano의 제한된 CUDA 메모리 때문에 CPU 사용

# ========================================
# [2] 모델 경로
# ========================================
YOLO_MODEL_PATH = os.path.join(MODEL_DIR, 'set_1000_YOLO26s_best.pt')  # YOLO eye detector 모델
CLASSIFIER_MODEL_PATH = os.path.join(MODEL_DIR, 'Augmented_EffNet_V1_B0_best.pth')

# ========================================
# [3] 서버 설정
# ========================================
SERVER_IP = _get_env_str('SERVER_IP', _get_env_str('SERVER_HOST', '0.0.0.0'))
SERVER_PORT = _get_env_int('SERVER_PORT', 5000)
DEBUG_MODE = _get_env_bool('DEBUG_MODE', False)

# ========================================
# [3-1] 카메라 설정
# ========================================
CAMERA_DEVICE_INDEX = _get_env_int('CAMERA_DEVICE_INDEX', 0)

# ========================================
# [4] YOLO 검출 임계값
# ========================================
YOLO_CONF_THRESHOLD = _get_env_float('YOLO_CONF_THRESHOLD', 0.5)
YOLO_IOU_THRESHOLD = _get_env_float('YOLO_IOU_THRESHOLD', 0.45)
YOLO_INPUT_SIZE = _get_env_int('YOLO_INPUT_SIZE', 640)
YOLO_STATUS_CONF_THRESHOLD = _get_env_float('YOLO_STATUS_CONF_THRESHOLD', 0.25)

# ========================================
# [5] 분류 모델 설정
# ========================================
CLASSIFIER_INPUT_SIZE = (224, 224)       # EfficientNet 입력 크기
CLASSIFIER_CONFIDENCE_THRESHOLD = _get_env_float('CLASSIFIER_CONFIDENCE_THRESHOLD', 0.7)

# ========================================
# [6] 질환 분류 클래스 (5개)
# ========================================
DISEASE_CLASSES = {
    0: '결막염 (Conjunctivitis)',
    1: '다래끼 (Eyelid)',
    2: '백내장 (Cataract)',
    3: '일반 (Normal)',
    4: '포도막염 (Uveitis)'
}

# ========================================
# [7] 홍채 제거 설정
# ========================================
IRIS_REMOVAL_ENABLED = _get_env_bool('IRIS_REMOVAL_ENABLED', True)
IRIS_THRESHOLD = _get_env_float('IRIS_THRESHOLD', 0.3)

# ========================================
# [8] 로깅 설정
# ========================================
LOG_DIR = os.path.join(BASE_DIR, 'logs')
LOG_FORMAT = 'csv'               # 'csv' 또는 'db'
os.makedirs(LOG_DIR, exist_ok=True)

# ========================================
# [9] 이미지 처리 설정
# ========================================
IMAGE_SAVE_DIR = os.path.join(BASE_DIR, 'web', 'static', 'captures')
os.makedirs(IMAGE_SAVE_DIR, exist_ok=True)

# ========================================
# [10] 자동 촬영 설정
# ========================================
# 중심점 거리 임계값: 중심점이 가이드라인 중심으로부터 
# 30픽셀 이내일 때 자동 촬영 준비
AUTO_DIST_THRESHOLD = _get_env_int('AUTO_DIST_THRESHOLD', 30)

# 눈 크기 비율 임계값: 가이드라인 대비 
# 눈의 크기가 이 범위 내에 있을 때 적절한 위치로 판단
AUTO_SCALE_MIN = _get_env_float('AUTO_SCALE_MIN', 0.8)
AUTO_SCALE_MAX = _get_env_float('AUTO_SCALE_MAX', 1.1)

# 자동 촬영 대기 프레임: 조건을 만족한 후 
# 이 프레임 수만큼 유지되면 자동 촬영
AUTO_CAPTURE_HOLD_FRAMES = _get_env_int('AUTO_CAPTURE_HOLD_FRAMES', 10)
