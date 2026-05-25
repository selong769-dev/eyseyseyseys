# security_utils.py
import os
import re
import hashlib
import hmac

_PHONE_RE = re.compile(r"\D+")
HASH_PEPPER = os.environ.get("HASH_PEPPER")  # 필수: 환경변수로 주입

def _require_pepper() -> str:
    if not HASH_PEPPER:
        raise RuntimeError(
            "HASH_PEPPER 환경변수가 설정되어야 합니다.\n"
            "예) Linux/Jetson: export HASH_PEPPER='your-secret'\n"
            "예) Windows PowerShell: $env:HASH_PEPPER='your-secret'"
        )
    return HASH_PEPPER

def normalize_phone(phone: str) -> str:
    """
    010-1234-5678 -> 01012345678
    """
    if phone is None:
        raise ValueError("phone is None")
    digits = _PHONE_RE.sub("", str(phone))
    if len(digits) < 9:
        raise ValueError(f"phone looks too short: {digits}")
    return digits

def phone_hash_id(phone: str) -> str:
    """
    사용자 고유 ID로 사용할 phone_hash 생성.
    - 동일 전화번호 -> 동일 해시(중복 가입 방지/조회 가능)
    - 보안: pepper(서버 비밀값) 섞어서 사전 공격 난이도 상승
    """
    pepper = _require_pepper()
    norm = normalize_phone(phone)
    msg = f"{norm}|{pepper}".encode("utf-8")
    return hashlib.sha256(msg).hexdigest()

def secure_equals(a: str, b: str) -> bool:
    return hmac.compare_digest(a, b)
