"""CRUD Layer for User Management - Database Operations Only.
This layer contains ONLY SQL operations for user-related data.
All business logic is in controls/auth_service.py"""
from typing import Optional, List
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from modules.db_init import User


class UserCRUD:
    """用戶 CRUD 層 - 只負責數據庫操作（增刪改查）。"""
    
    # ============ User Create Operations ============
    @staticmethod
    def create_user(db: Session, username: str, email: str, password_hash: str) -> User:
        """創建新用戶。"""
        try:
            user = User(username=username, email=email, password_hash=password_hash)
            db.add(user)
            db.commit()
            db.refresh(user)
            return user
        except IntegrityError:
            db.rollback()
            raise ValueError("Username or email already exists")
    
    # ============ User Read Operations ============
    @staticmethod
    def get_user_by_username(db: Session, username: str) -> Optional[User]:
        """根據用戶名獲取用戶。"""
        return db.query(User).filter(User.username == username).first()
    
    @staticmethod
    def get_user_by_email(db: Session, email: str) -> Optional[User]:
        """根據郵箱獲取用戶。"""
        return db.query(User).filter(User.email == email).first()
    
    @staticmethod
    def get_user_by_id(db: Session, user_id: int) -> Optional[User]:
        """根據 ID 獲取用戶。"""
        return db.query(User).filter(User.uid == user_id).first()
    
    @staticmethod
    def get_all_users(db: Session, limit: int = 100) -> List[User]:
        """獲取所有用戶（管理員功能）。"""
        return db.query(User).limit(limit).all()
    
    # ============ User Update Operations ============
    @staticmethod
    def update_user(db: Session, user: User, **kwargs) -> User:
        """更新用戶信息。"""
        for key, value in kwargs.items():
            if hasattr(user, key):
                setattr(user, key, value)
        db.commit()
        db.refresh(user)
        return user
    
    @staticmethod
    def update_user_by_id(db: Session, user_id: int, **kwargs) -> Optional[User]:
        """根據用戶 ID 更新用戶信息。"""
        user = db.query(User).filter(User.uid == user_id).first()
        if user:
            for key, value in kwargs.items():
                if hasattr(user, key):
                    setattr(user, key, value)
            db.commit()
            db.refresh(user)
        return user
    
    # ============ User Delete Operations ============
    @staticmethod
    def delete_user(db: Session, user_id: int) -> bool:
        """刪除用戶及其所有相關數據。"""
        user = db.query(User).filter(User.uid == user_id).first()
        if user:
            db.delete(user)
            db.commit()
            return True
        return False
