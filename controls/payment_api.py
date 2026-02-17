"""FastAPI routes for Payment (Google Play) operations."""
from fastapi import APIRouter, Depends, HTTPException, status, Header
from sqlalchemy.orm import Session
from typing import Optional, Dict, Any
from pydantic import BaseModel
import json

from modules.db_connect import get_db
from controls.pdf_service import PDFEditorService
from controls.tools import verify_token

router = APIRouter(prefix="/api/payment", tags=["Payment"])


# Pydantic Models
class GooglePlayValidationRequest(BaseModel):
    """Google Play 購買驗證請求。"""
    transaction_id: str
    product_id: str
    receipt_data: str


class MockGooglePlayResponse(BaseModel):
    """Google Play 模擬響應。"""
    success: bool
    amount: int  # 美分
    quota_to_add: int


# 模擬的商品配置
PRODUCT_QUOTA_MAP = {
    "pdf_editor_50_pages": {
        "amount": 100,  # $1.00
        "quota": 50
    },
    "pdf_editor_5000_pages": {
        "amount": 5000,  # $50.00
        "quota": 5000
    }
}


def get_user_id(authorization: Optional[str] = Header(None)) -> int:
    """
    從 Authorization header 中提取並驗證用戶 ID。
    
    Args:
        authorization: Authorization header 值
    
    Returns:
        用戶ID
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authorization header"
        )
    
    try:
        token = authorization.replace("Bearer ", "")
        user_data = verify_token(token)
        return user_data.get("user_id", 1)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )


# Endpoints

# 驗證 Google Play 購買並增加額度。
@router.post("/google-play/validate", response_model=Dict[str, Any])
def validate_google_play_purchase(
    request: GooglePlayValidationRequest,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    邏輯：
    1. 驗證 Google Play 收據（Mock 實現）
    2. 檢查商品 ID 是否有效
    3. 創建交易記錄
    4. 增加用戶付費額度
    
    Args:
        request: Google Play 驗證請求
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        Dict: 驗證結果和額度更新信息
        
        示例返回值：
        {
            "success": True,
            "message": "Purchase verified and quota added",
            "data": {
                "transaction_id": "GPA.xxx",
                "product_id": "pdf_editor_100_pages",
                "quota_added": 100,
                "quota_remaining": 150
            }
        }
    
    Raises:
        HTTPException(400): 無效的商品 ID 或收據
        HTTPException(401): 未授權
        HTTPException(500): 伺服器錯誤
    """
    try:
        # 步驟 1：驗證商品 ID
        if request.product_id not in PRODUCT_QUOTA_MAP:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid product ID"
            )
        
        product_info = PRODUCT_QUOTA_MAP[request.product_id]
        
        # 步驟 2：模擬 Google Play 驗證
        # 實際環境應調用 Google Play Developer API
        # 這裡簡化為檢查 receipt_data 不為空
        if not request.receipt_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid receipt data"
            )
        
        # 步驟 3：處理支付
        result = PDFEditorService.process_payment(
            db,
            user_id,
            transaction_id=request.transaction_id,
            product_id=request.product_id,
            amount=product_info["amount"],
            quota_to_add=product_info["quota"],
            receipt_data=request.receipt_data
        )
        
        if not result["success"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=result["message"]
            )
        
        return {
            "success": True,
            "message": "Purchase verified and quota added",
            "data": result
        }
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )

# 獲取可用的商品列表及其配置。
@router.get("/products", response_model=Dict[str, Any])
def get_available_products() -> Dict[str, Any]:
    try:
        products = []
        for product_id, info in PRODUCT_QUOTA_MAP.items():
            products.append({
                "product_id": product_id,
                "amount": info["amount"],
                "amount_formatted": f"${info['amount'] / 100:.2f}",
                "quota": info["quota"],
                "currency": "USD"
            })
        
        return {
            "success": True,
            "data": {
                "products": products
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 獲取用戶的交易歷史記錄。
@router.get("/transactions", response_model=Dict[str, Any])
def get_transaction_history(
    limit: int = 50,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    Args:
        limit: 返回的最大交易數
        db: 數據庫會話
        user_id: 用戶ID
    """
    try:
        from modules.pdf_crud import PDFEditorCRUD
        
        transactions = PDFEditorCRUD.get_user_transactions(db, user_id, limit)
        
        return {
            "success": True,
            "data": {
                "transactions": [
                    {
                        "transaction_id": t.transaction_id,
                        "product_id": t.product_id,
                        "amount": t.amount,
                        "quota_added": t.quota_added,
                        "status": t.status,
                        "created_at": t.created_at.isoformat()
                    }
                    for t in transactions
                ],
                "total": len(transactions)
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 模擬一個 Google Play 購買（用於測試）。
@router.post("/mock-purchase", response_model=Dict[str, Any])
def mock_purchase(
    product_id: str,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    直接增加額度，無需驗證。
    
    Args:
        product_id: 商品 ID
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        購買結果
    """
    try:
        if product_id not in PRODUCT_QUOTA_MAP:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid product ID"
            )
        
        product_info = PRODUCT_QUOTA_MAP[product_id]
        
        # 生成模擬交易 ID
        import uuid
        transaction_id = f"MOCK-{uuid.uuid4().hex[:16].upper()}"
        
        # 處理支付
        result = PDFEditorService.process_payment(
            db,
            user_id,
            transaction_id=transaction_id,
            product_id=product_id,
            amount=product_info["amount"],
            quota_to_add=product_info["quota"],
            receipt_data="MOCK_RECEIPT"
        )
        
        if not result["success"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=result["message"]
            )
        
        return {
            "success": True,
            "message": "Mock purchase completed",
            "data": result
        }
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )
