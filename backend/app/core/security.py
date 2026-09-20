import hashlib
import os
from typing import Optional

def hash_emergency_password(password: str, salt: Optional[str] = None) -> str:
    """Hashes the emergency duress password with SHA-256 and salt."""
    if not salt:
        salt = os.urandom(16).hex()
    hashed = hashlib.sha256((salt + password).encode("utf-8")).hexdigest()
    return f"{salt}${hashed}"

def verify_emergency_password(plain_password: str, hashed_value: str) -> bool:
    """Verifies whether plain_password matches the hashed emergency password."""
    try:
        salt, hashed = hashed_value.split("$", 1)
        test_hash = hashlib.sha256((salt + plain_password).encode("utf-8")).hexdigest()
        return test_hash == hashed
    except Exception:
        return False
