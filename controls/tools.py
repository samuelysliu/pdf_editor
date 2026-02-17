"""Auth and utility tools."""
from fastapi import HTTPException, status
from typing import Dict, Any, Optional
from datetime import datetime, timedelta
from passlib.context import CryptContext
import jwt

# 密碼加密設置（使用 argon2）
pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")

# JWT 設置
SECRET_KEY = "your-secret-key-change-in-production"  # 生產環境應使用環境變數
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30 * 24  # 30 天


def hash_password(password: str) -> str:
    """將密碼加密。"""
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """驗證密碼是否匹配。"""
    return pwd_context.verify(plain_password, hashed_password)


def create_access_token(data: Dict[str, Any], expires_delta: Optional[timedelta] = None) -> str:
    """
    生成 JWT token。
    
    Args:
        data: 要編碼的數據
        expires_delta: token 過期時間間隔
        
    Returns:
        JWT token 字符串
    """
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def verify_token(token: Optional[str] = None) -> Dict[str, Any]:
    """
    驗證 JWT token 並返回用戶信息。
    
    Args:
        token: JWT token 字符串
        
    Returns:
        解碼後的 token 數據
        
    Raises:
        HTTPException: Token 無效或過期
    """
    if not token or token == "":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid token"
        )
    
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired"
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )
