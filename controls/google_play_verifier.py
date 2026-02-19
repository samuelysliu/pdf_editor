"""
Google Play 收據驗證服務

此模組使用 Google Play Developer API 驗證真實的購買收據及訂閱收據。

⚠️ 設定步驟：
1. 前往 Google Cloud Console → API 與服務 → 啟用「Google Play Android Developer API」
2. 建立服務帳戶 → 下載 JSON 金鑰檔案
3. 前往 Google Play Console → 設定 → API 存取權 → 綁定該服務帳戶
4. 將 JSON 金鑰檔案路徑填入下方 GOOGLE_SERVICE_ACCOUNT_KEY_PATH
5. 將你的 App Package Name 填入 GOOGLE_PLAY_PACKAGE_NAME
"""

import os
import json
import logging
from typing import Dict, Any, Optional

logger = logging.getLogger(__name__)

# Google Cloud 服務帳戶 JSON 金鑰檔案路徑
GOOGLE_SERVICE_ACCOUNT_KEY_PATH: str = os.environ.get(
    "GOOGLE_SERVICE_ACCOUNT_KEY_PATH",
)

# Google Play 上的 App Package Name
GOOGLE_PLAY_PACKAGE_NAME: str = os.environ.get(
    "GOOGLE_PLAY_PACKAGE_NAME",
)

# ============================================================

# 建立 Google Play Developer API 客戶端
def _get_android_publisher_service():
    """
    Returns:
        googleapiclient.discovery.Resource: androidpublisher API 服務
    """
    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
    except ImportError:
        raise RuntimeError(
            "請先安裝依賴：pip install google-api-python-client google-auth"
        )

    if not GOOGLE_SERVICE_ACCOUNT_KEY_PATH:
        raise ValueError(
            "未設定 GOOGLE_SERVICE_ACCOUNT_KEY_PATH，"
            "請在 controls/google_play_verifier.py 或環境變數中設定。"
        )

    if not os.path.exists(GOOGLE_SERVICE_ACCOUNT_KEY_PATH):
        raise FileNotFoundError(
            f"找不到服務帳戶金鑰檔案：{GOOGLE_SERVICE_ACCOUNT_KEY_PATH}"
        )

    credentials = service_account.Credentials.from_service_account_file(
        GOOGLE_SERVICE_ACCOUNT_KEY_PATH,
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )

    service = build("androidpublisher", "v3", credentials=credentials)
    return service

# 驗證一次性購買（Managed Product / Consumable）。
def verify_one_time_purchase(
    product_id: str,
    purchase_token: str,
    package_name: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Args:
        product_id: 商品 ID（與 Google Play Console 一致）
        purchase_token: 來自客戶端的 purchaseToken
        package_name: App Package Name（預設使用 GOOGLE_PLAY_PACKAGE_NAME）

    Returns:
        {
            "valid": True/False,
            "purchase_state": 0=purchased, 1=canceled, 2=pending,
            "consumption_state": 0=not consumed, 1=consumed,
            "order_id": "GPA.xxxx",
            "purchase_time_millis": "...",
            "raw_response": { ... }
        }
    """
    pkg = package_name or GOOGLE_PLAY_PACKAGE_NAME
    if not pkg:
        raise ValueError(
            "未設定 GOOGLE_PLAY_PACKAGE_NAME，"
            "請在 controls/google_play_verifier.py 或環境變數中設定。"
        )

    try:
        service = _get_android_publisher_service()
        result = (
            service.purchases()
            .products()
            .get(
                packageName=pkg,
                productId=product_id,
                token=purchase_token,
            )
            .execute()
        )

        purchase_state = result.get("purchaseState", -1)
        is_valid = purchase_state == 0  # 0 = purchased

        logger.info(
            f"[GooglePlayVerifier] One-time verify: product={product_id}, "
            f"valid={is_valid}, state={purchase_state}"
        )

        return {
            "valid": is_valid,
            "purchase_state": purchase_state,
            "consumption_state": result.get("consumptionState", -1),
            "order_id": result.get("orderId", ""),
            "purchase_time_millis": result.get("purchaseTimeMillis", ""),
            "raw_response": result,
        }

    except Exception as e:
        logger.error(f"[GooglePlayVerifier] One-time verify error: {e}")
        return {
            "valid": False,
            "error": str(e),
            "raw_response": None,
        }

# 驗證訂閱購買（Subscription）。
def verify_subscription(
    subscription_id: str,
    purchase_token: str,
    package_name: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Args:
        subscription_id: 訂閱商品 ID（與 Google Play Console 一致）
        purchase_token: 來自客戶端的 purchaseToken
        package_name: App Package Name（預設使用 GOOGLE_PLAY_PACKAGE_NAME）

    Returns:
        {
            "valid": True/False,
            "expiry_time_millis": "...",       # 到期時間（毫秒時間戳）
            "auto_renewing": True/False,       # 是否自動續訂
            "payment_state": 0/1/2/3,          # 0=pending, 1=received, 2=free trial, 3=deferred
            "cancel_reason": None/0/1/2/3,     # 取消原因
            "order_id": "GPA.xxxx",
            "raw_response": { ... }
        }
    """
    pkg = package_name or GOOGLE_PLAY_PACKAGE_NAME
    if not pkg:
        raise ValueError(
            "未設定 GOOGLE_PLAY_PACKAGE_NAME，"
            "請在 controls/google_play_verifier.py 或環境變數中設定。"
        )

    try:
        service = _get_android_publisher_service()
        result = (
            service.purchases()
            .subscriptions()
            .get(
                packageName=pkg,
                subscriptionId=subscription_id,
                token=purchase_token,
            )
            .execute()
        )

        expiry_millis = int(result.get("expiryTimeMillis", 0))
        # 訂閱有效 = 到期時間在未來
        import time
        now_millis = int(time.time() * 1000)
        is_valid = expiry_millis > now_millis

        logger.info(
            f"[GooglePlayVerifier] Subscription verify: id={subscription_id}, "
            f"valid={is_valid}, expires={expiry_millis}"
        )

        return {
            "valid": is_valid,
            "expiry_time_millis": str(expiry_millis),
            "auto_renewing": result.get("autoRenewing", False),
            "payment_state": result.get("paymentState", -1),
            "cancel_reason": result.get("cancelReason"),
            "order_id": result.get("orderId", ""),
            "raw_response": result,
        }

    except Exception as e:
        logger.error(f"[GooglePlayVerifier] Subscription verify error: {e}")
        return {
            "valid": False,
            "error": str(e),
            "raw_response": None,
        }


def is_configured() -> bool:
    """檢查 Google Play 驗證是否已正確設定"""
    return bool(GOOGLE_SERVICE_ACCOUNT_KEY_PATH) and bool(GOOGLE_PLAY_PACKAGE_NAME)
