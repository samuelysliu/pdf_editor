"""CRUD Layer for Payment - Database Operations Only.
This layer contains ONLY SQL operations for transactions, subscriptions, and quota (payment-related).
All business logic is in controls/pdf_service.py"""
from typing import Dict, Any, Optional, List
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from modules.db_init import User, Transaction, Subscription


class PaymentCRUD:
    """購買相關 CRUD 層 — 負責交易、訂閱、額度（付費）的數據庫操作。"""

    # ============ Quota Operations ============
    @staticmethod
    def get_quota_info(db: Session, user_id: int) -> Optional[Dict[str, Any]]:
        """獲取用戶當前額度信息。"""
        user = db.query(User).filter(User.uid == user_id).first()
        if not user:
            return None
        return {
            "quota": user.quota
        }

    @staticmethod
    def add_quota(db: Session, user_id: int, pages: int) -> User:
        """增加用戶額度。"""
        user = db.query(User).filter(User.uid == user_id).first()
        if user:
            user.quota += pages
            db.commit()
            db.refresh(user)
        return user

    # ============ Transaction Operations ============
    @staticmethod
    def create_transaction(db: Session, user_id: int, **kwargs) -> Transaction:
        """創建交易記錄。"""
        try:
            transaction = Transaction(user_id=user_id, **kwargs)
            db.add(transaction)
            db.commit()
            db.refresh(transaction)
            return transaction
        except IntegrityError:
            db.rollback()
            raise ValueError("Transaction already exists")

    @staticmethod
    def get_transaction(db: Session, transaction_id: str, user_id: int) -> Optional[Transaction]:
        """根據交易 ID 獲取交易記錄。"""
        return db.query(Transaction).filter(
            Transaction.transaction_id == transaction_id,
            Transaction.user_id == user_id
        ).first()

    @staticmethod
    def get_user_transactions(db: Session, user_id: int, limit: int = 50) -> List[Transaction]:
        """獲取用戶的交易記錄。"""
        return db.query(Transaction).filter(
            Transaction.user_id == user_id
        ).order_by(Transaction.created_at.desc()).limit(limit).all()

    @staticmethod
    def update_transaction_status(db: Session, transaction: Transaction, status: str) -> Transaction:
        """更新交易狀態。"""
        transaction.status = status
        db.commit()
        db.refresh(transaction)
        return transaction

    # ============ Subscription Operations ============
    @staticmethod
    def create_subscription(db: Session, user_id: int, **kwargs) -> Subscription:
        """創建訂閱記錄。"""
        sub = Subscription(user_id=user_id, **kwargs)
        db.add(sub)
        db.commit()
        db.refresh(sub)
        return sub

    @staticmethod
    def get_active_subscription(db: Session, user_id: int) -> "Subscription | None":
        """獲取用戶當前有效的訂閱。"""
        now = datetime.utcnow()
        return db.query(Subscription).filter(
            Subscription.user_id == user_id,
            Subscription.status == "active",
            Subscription.end_date > now,
        ).order_by(Subscription.end_date.desc()).first()

    @staticmethod
    def get_user_subscriptions(db: Session, user_id: int, limit: int = 20):
        """獲取用戶的訂閱歷史。"""
        return db.query(Subscription).filter(
            Subscription.user_id == user_id
        ).order_by(Subscription.created_at.desc()).limit(limit).all()

    @staticmethod
    def expire_subscription(db: Session, subscription_id: int) -> "Subscription | None":
        """將訂閱標記為過期。"""
        sub = db.query(Subscription).filter(Subscription.id == subscription_id).first()
        if sub:
            sub.status = "expired"
            db.commit()
            db.refresh(sub)
        return sub

    @staticmethod
    def cancel_subscription(db: Session, subscription_id: int) -> "Subscription | None":
        """取消訂閱。"""
        sub = db.query(Subscription).filter(Subscription.id == subscription_id).first()
        if sub:
            sub.status = "cancelled"
            db.commit()
            db.refresh(sub)
        return sub
