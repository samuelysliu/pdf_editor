"""FastAPI routes for User Authentication."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import timedelta
import logging

from modules.db_connect import get_db
from modules.user_crud import UserCRUD
from controls.tools import (
    hash_password,
    verify_password,
    create_access_token,
    verify_token,
    ACCESS_TOKEN_EXPIRE_MINUTES
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/users", tags=["Authentication"])


# Pydantic Models
# 用戶註冊模型
class UserRegister(BaseModel):
    username: str
    email: EmailStr
    password: str

# 用戶登入模型
class UserLogin(BaseModel):
    username: str
    password: str

# Token Response 模型
class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    username: str

# Google 登入請求模型
class GoogleLoginRequest(BaseModel):
    id_token: str  # Google Sign-In 的 id_token
    email: Optional[str] = None
    display_name: Optional[str] = None

#用戶信息 Response 模型
class UserResponse(BaseModel):
    user_id: int
    username: str
    email: str

# 用戶註冊
@router.post("/register", response_model=TokenResponse)
def register(
    request: UserRegister,
    db: Session = Depends(get_db)
) -> TokenResponse:
    try:
        # 檢查用戶名是否已存在
        existing_user = UserCRUD.get_user_by_username(db, request.username)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )

        # 檢查郵箱是否已存在
        existing_email = UserCRUD.get_user_by_email(db, request.email)
        if existing_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered"
            )

        # 驗證密碼長度
        if len(request.password) < 6:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Password must be at least 6 characters"
            )

        # 創建新用戶
        password_hash = hash_password(request.password)
        user = UserCRUD.create_user(
            db,
            username=request.username,
            email=request.email,
            password_hash=password_hash
        )

        # 生成 token
        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"user_id": user.uid, "username": user.username},
            expires_delta=access_token_expires
        )

        return TokenResponse(
            access_token=access_token,
            user_id=user.uid,
            username=user.username
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )

# 用戶登入
@router.post("/login", response_model=TokenResponse)
def login(
    request: UserLogin,
    db: Session = Depends(get_db)
) -> TokenResponse:
    try:
        # 查找用戶
        user = UserCRUD.get_user_by_username(db, request.username)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password"
            )

        # 驗證密碼
        if not verify_password(request.password, user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password"
            )

        # 生成 token
        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"user_id": user.uid, "username": user.username},
            expires_delta=access_token_expires
        )

        return TokenResponse(
            access_token=access_token,
            user_id=user.uid,
            username=user.username
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )

# 獲取用戶個人資料
@router.get("/profile", response_model=UserResponse)
def get_profile(
    token: str = Depends(lambda auth: auth.replace("Bearer ", "") if auth else None),
    db: Session = Depends(get_db)
) -> UserResponse:
    try:
        token_data = verify_token(token)
        user_id = token_data.get("user_id")

        user = UserCRUD.get_user_by_id(db, user_id)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )

        return UserResponse(
            user_id=user.uid,
            username=user.username,
            email=user.email
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )


# ============================================================
#  ⚠️ Google OAuth 設定
# ============================================================
# 你的 Google OAuth Client ID（從 Google Cloud Console 取得）
# 用於後端驗證 id_token 的合法性
import os
GOOGLE_CLIENT_ID: str = os.environ.get(
    "GOOGLE_OAUTH_CLIENT_ID",
    ""  # TODO: 填入你的 Google OAuth Client ID（Web 或 Android）
)


def _verify_google_id_token(id_token: str) -> dict:
    """
    驗證 Google id_token 並取得用戶資訊。

    Returns:
        {
            "sub": "Google user ID",
            "email": "user@gmail.com",
            "name": "Display Name",
            ...
        }
    """
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        idinfo = google_id_token.verify_oauth2_token(
            id_token,
            google_requests.Request(),
            GOOGLE_CLIENT_ID if GOOGLE_CLIENT_ID else None,
        )

        # 驗證 issuer
        if idinfo.get("iss") not in [
            "accounts.google.com",
            "https://accounts.google.com",
        ]:
            raise ValueError("Invalid issuer")

        return idinfo

    except Exception as e:
        logger.error(f"[GoogleAuth] id_token 驗證失敗: {e}")
        raise ValueError(f"Invalid Google id_token: {e}")


# Google 第三方登入（自動註冊 + 登入）
@router.post("/google-login", response_model=TokenResponse)
def google_login(
    request: GoogleLoginRequest,
    db: Session = Depends(get_db),
) -> TokenResponse:
    """
    流程：
    1. 驗證 Google id_token
    2. 用 google_id (sub) 查找是否已有帳號
    3. 若無帳號 → 自動建立（免密碼）
    4. 產生 JWT token 回傳
    """
    try:
        # 步驟 1：驗證 Google id_token
        google_info = _verify_google_id_token(request.id_token)
        google_id = google_info["sub"]
        email = google_info.get("email") or request.email or ""
        display_name = google_info.get("name") or request.display_name or email.split("@")[0]

        # 步驟 2：查找用戶
        user = UserCRUD.get_user_by_google_id(db, google_id)

        if not user:
            # 如果 email 已被傳統帳號使用，綁定 google_id
            user = UserCRUD.get_user_by_email(db, email)
            if user:
                user.google_id = google_id
                db.commit()
                db.refresh(user)
            else:
                # 步驟 3：自動建立新帳號
                # 確保 username 唯一
                base_username = display_name.replace(" ", "_")[:30]
                username = base_username
                counter = 1
                while UserCRUD.get_user_by_username(db, username):
                    username = f"{base_username}_{counter}"
                    counter += 1

                user = UserCRUD.create_google_user(
                    db,
                    google_id=google_id,
                    email=email,
                    username=username,
                )

        # 步驟 4：產生 JWT token
        access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = create_access_token(
            data={"user_id": user.uid, "username": user.username},
            expires_delta=access_token_expires,
        )

        return TokenResponse(
            access_token=access_token,
            user_id=user.uid,
            username=user.username,
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[GoogleAuth] 登入失敗: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e),
        )
