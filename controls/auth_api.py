"""FastAPI routes for User Authentication."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from datetime import timedelta

from modules.db_connect import get_db
from modules.user_crud import UserCRUD
from controls.tools import (
    hash_password,
    verify_password,
    create_access_token,
    verify_token,
    ACCESS_TOKEN_EXPIRE_MINUTES
)

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
