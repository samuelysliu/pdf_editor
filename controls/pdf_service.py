"""Business Logic Layer for PDF Editor.
All business logic for quota management, PDF operations, and payment handling.
CRUD operations are delegated to modules/pdf_crud.py and modules/user_crud.py"""
import os
from typing import Dict, Any, Optional, List
from io import BytesIO
from sqlalchemy.orm import Session
from PyPDF2 import PdfMerger, PdfReader
from modules.pdf_crud import PDFEditorCRUD
from modules.user_crud import UserCRUD


class PDFEditorService:
    """PDF 編輯器業務邏輯層。"""

    # ============ Quota Management ============
    @staticmethod
    def check_and_deduct_quota(
        db: Session,
        user_id: int,
        pages_required: int
    ) -> Dict[str, Any]:
        """
        檢查額度並扣除。

        Args:
            db: 數據庫會話
            user_id: 用戶 ID
            pages_required: 需要的頁數

        Returns:
            包含額度扣除結果的字典

        Raises:
            ValueError: 用戶不存在
        """
        user = UserCRUD.get_user_by_id(db, user_id)
        if not user:
            raise ValueError("User not found")

        # 檢查額度是否足夠
        if user.quota < pages_required:
            return {
                "success": False,
                "message": "Insufficient quota",
                "quota_needed": pages_required,
                "quota_available": user.quota
            }

        # 扣除額度
        PDFEditorCRUD.deduct_quota(db, user_id, pages_required)

        # 刷新用戶數據並返回結果
        user = UserCRUD.get_user_by_id(db, user_id)

        return {
            "success": True,
            "message": "Quota deducted successfully",
            "quota_used": pages_required,
            "quota_remaining": user.quota
        }

    @staticmethod
    def get_quota_status(db: Session, user_id: int) -> Dict[str, Any]:
        """
        獲取用戶的當前額度狀態。

        Args:
            db: 數據庫會話
            user_id: 用戶 ID

        Returns:
            包含額度狀態的字典
        """
        user = UserCRUD.get_user_by_id(db, user_id)
        if not user:
            raise ValueError("User not found")

        return {
            "quota": user.quota
        }

    # ============ PDF File Operations ============
    @staticmethod
    def upload_pdf(
        db: Session,
        user_id: int,
        filename: str,
        file_path: str,
        file_size: int,
        page_count: int
    ) -> Dict[str, Any]:
        """
        處理 PDF 上傳並扣除額度。
        """
        # 檢查並扣除額度
        quota_result = PDFEditorService.check_and_deduct_quota(db, user_id, page_count)

        if not quota_result["success"]:
            return {
                "success": False,
                "message": quota_result["message"],
                "quota_info": quota_result
            }

        # 創建 PDF 文件記錄
        pdf_file = PDFEditorCRUD.create_pdf_file(
            db,
            user_id,
            filename=filename,
            file_path=file_path,
            file_size=file_size,
            page_count=page_count,
            quota_used=page_count
        )

        return {
            "success": True,
            "message": "PDF uploaded successfully",
            "pdf_file": {
                "id": pdf_file.id,
                "filename": pdf_file.filename,
                "page_count": pdf_file.page_count,
                "quota_used": pdf_file.quota_used
            },
            "quota_remaining": quota_result["quota_remaining"]
        }

    @staticmethod
    def get_pdf_files(db: Session, user_id: int, limit: int = 50) -> Dict[str, Any]:
        """獲取用戶的 PDF 文件列表。"""
        pdf_files = PDFEditorCRUD.get_user_pdf_files(db, user_id, limit)

        return {
            "success": True,
            "data": {
                "pdf_files": [
                    {
                        "id": pdf.id,
                        "filename": pdf.filename,
                        "page_count": pdf.page_count,
                        "quota_used": pdf.quota_used,
                        "created_at": pdf.created_at.isoformat()
                    }
                    for pdf in pdf_files
                ],
                "total": len(pdf_files)
            }
        }

    # ============ Payment Operations ============
    # 合併多個 PDF 文件。
    @staticmethod
    def merge_pdfs(
        db: Session,
        user_id: int,
        pdf_ids: List[int],
        output_filename: str
    ) -> Dict[str, Any]:
        """
        流程：
        1. 驗證所有 PDF 都屬於該用戶且文件存在
        2. 使用 PyPDF2 合併
        3. 保存合併後的文件
        4. 在 DB 建立新的 PDFFile 記錄（不扣額度，因為上傳時已扣過）

        Args:
            db: 數據庫會話
            user_id: 用戶 ID
            pdf_ids: 要合併的 PDF 文件 ID 列表（按順序合併）
            output_filename: 輸出文件名

        Returns:
            包含合併結果的字典

        Raises:
            ValueError: PDF 不存在、不屬於用戶、或文件缺失
        """
        if len(pdf_ids) < 2:
            raise ValueError("At least 2 PDF files are required for merging")

        # 去重並保持順序
        seen = set()
        unique_ids = []
        for pid in pdf_ids:
            if pid not in seen:
                seen.add(pid)
                unique_ids.append(pid)

        # 查詢所有 PDF 記錄
        pdf_files = PDFEditorCRUD.get_multiple_pdf_files(db, unique_ids, user_id)

        if len(pdf_files) != len(unique_ids):
            found_ids = {pdf.id for pdf in pdf_files}
            missing_ids = [pid for pid in unique_ids if pid not in found_ids]
            raise ValueError(f"PDF files not found or access denied: {missing_ids}")

        # 驗證所有文件實際存在於磁碟
        for pdf in pdf_files:
            if not os.path.exists(pdf.file_path):
                raise ValueError(f"PDF file missing on disk: {pdf.filename} (id={pdf.id})")

        # 使用 PyPDF2 合併 PDF
        merger = PdfMerger()
        total_pages = 0

        try:
            for pdf in pdf_files:
                merger.append(pdf.file_path)
                total_pages += pdf.page_count

            # 確保輸出目錄存在
            output_dir = f"uploads/{user_id}"
            os.makedirs(output_dir, exist_ok=True)

            # 確保文件名以 .pdf 結尾
            if not output_filename.lower().endswith('.pdf'):
                output_filename += '.pdf'

            output_path = os.path.join(output_dir, output_filename)

            # 如果同名文件已存在，自動加編號
            base_name, ext = os.path.splitext(output_filename)
            counter = 1
            while os.path.exists(output_path):
                output_filename = f"{base_name}_{counter}{ext}"
                output_path = os.path.join(output_dir, output_filename)
                counter += 1

            # 寫入合併文件
            with open(output_path, "wb") as output_file:
                merger.write(output_file)
        finally:
            merger.close()

        # 獲取合併後的文件大小
        merged_file_size = os.path.getsize(output_path)

        # 建立新的 PDF 記錄（合併不額外扣額度）
        merged_pdf = PDFEditorCRUD.create_pdf_file(
            db,
            user_id,
            filename=output_filename,
            file_path=output_path,
            file_size=merged_file_size,
            page_count=total_pages,
            quota_used=0  # 合併不扣額度，原始檔案上傳時已扣過
        )

        return {
            "success": True,
            "message": "PDFs merged successfully",
            "merged_pdf": {
                "id": merged_pdf.id,
                "filename": merged_pdf.filename,
                "file_path": merged_pdf.file_path,
                "file_size": merged_file_size,
                "page_count": total_pages,
                "quota_used": 0
            },
            "source_pdfs": [
                {"id": pdf.id, "filename": pdf.filename, "page_count": pdf.page_count}
                for pdf in pdf_files
            ]
        }

    @staticmethod
    def process_payment(
        db: Session,
        user_id: int,
        transaction_id: str,
        product_id: str,
        amount: int,
        quota_to_add: int,
        receipt_data: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        處理支付並增加額度。

        Args:
            db: 數據庫會話
            user_id: 用戶 ID
            transaction_id: 交易 ID
            product_id: 商品 ID
            amount: 金額（美分）
            quota_to_add: 要增加的額度（頁數）
            receipt_data: Google Play 收據數據

        Returns:
            包含支付結果的字典
        """
        # 檢查交易是否已存在
        existing_transaction = PDFEditorCRUD.get_transaction(db, transaction_id, user_id)
        if existing_transaction:
            return {
                "success": False,
                "message": "Transaction already processed",
                "transaction_id": transaction_id
            }

        # 創建交易記錄
        transaction = PDFEditorCRUD.create_transaction(
            db,
            user_id,
            transaction_id=transaction_id,
            product_id=product_id,
            amount=amount,
            quota_added=quota_to_add,
            receipt_data=receipt_data,
            status="completed"
        )

        # 增加用戶額度
        PDFEditorCRUD.add_quota(db, user_id, quota_to_add)

        # 獲取更新後的額度信息
        quota_info = PDFEditorCRUD.get_quota_info(db, user_id)

        return {
            "success": True,
            "message": "Payment processed successfully",
            "transaction_id": transaction.transaction_id,
            "quota_added": quota_to_add,
            "quota_remaining": quota_info["quota"]
        }
