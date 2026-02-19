"""CRUD Layer for PDF Editor - Database Operations Only.
This layer contains ONLY SQL operations for creating, reading, updating, and deleting data.
All business logic is in controls/pdf_service.py"""
from typing import Dict, Any, Optional, List
from sqlalchemy.orm import Session
from modules.db_init import User, PDFFile, BrushStroke, PageImage


class PDFEditorCRUD:
    """PDF 編輯器 CRUD 層 - 只負責 PDF 相關的數據庫操作。

    注意：用戶相關的 CRUD 在 modules/user_crud.py
    購買/訂閱相關的 CRUD 在 modules/payment_crud.py
    """

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
    def deduct_quota(db: Session, user_id: int, pages: int) -> User:
        """扣除用戶額度。"""
        user = db.query(User).filter(User.uid == user_id).first()
        if user:
            user.quota -= pages
            db.commit()
            db.refresh(user)
        return user

    # ============ PDF File Operations ============
    @staticmethod
    def create_pdf_file(db: Session, user_id: int, **kwargs) -> PDFFile:
        """創建新的 PDF 文件記錄。"""
        pdf = PDFFile(user_id=user_id, **kwargs)
        db.add(pdf)
        db.commit()
        db.refresh(pdf)
        return pdf

    @staticmethod
    def get_pdf_file(db: Session, pdf_id: int, user_id: int) -> Optional[PDFFile]:
        """獲取用戶的 PDF 文件。"""
        return db.query(PDFFile).filter(
            PDFFile.id == pdf_id,
            PDFFile.user_id == user_id
        ).first()

    @staticmethod
    def get_multiple_pdf_files(db: Session, pdf_ids: List[int], user_id: int) -> List[PDFFile]:
        """根據 ID 列表獲取用戶的多個 PDF 文件（保持傳入順序）。"""
        pdfs = db.query(PDFFile).filter(
            PDFFile.id.in_(pdf_ids),
            PDFFile.user_id == user_id
        ).all()
        # 依照傳入的 pdf_ids 順序排列
        pdf_map = {pdf.id: pdf for pdf in pdfs}
        return [pdf_map[pid] for pid in pdf_ids if pid in pdf_map]

    @staticmethod
    def get_user_pdf_files(db: Session, user_id: int, limit: int = 50) -> List[PDFFile]:
        """獲取用戶的所有 PDF 文件。"""
        return db.query(PDFFile).filter(
            PDFFile.user_id == user_id
        ).order_by(PDFFile.created_at.desc()).limit(limit).all()

    @staticmethod
    def update_pdf_file(db: Session, pdf: PDFFile, **kwargs) -> PDFFile:
        """更新 PDF 文件信息。"""
        for key, value in kwargs.items():
            if hasattr(pdf, key):
                setattr(pdf, key, value)
        db.commit()
        db.refresh(pdf)
        return pdf

    @staticmethod
    def delete_pdf_file(db: Session, pdf_id: int, user_id: int) -> bool:
        """刪除 PDF 文件。"""
        pdf = db.query(PDFFile).filter(
            PDFFile.id == pdf_id,
            PDFFile.user_id == user_id
        ).first()
        if pdf:
            db.delete(pdf)
            db.commit()
            return True
        return False

    # ============ BrushStroke Operations ============
    @staticmethod
    def create_brush_stroke(db: Session, pdf_id: int, **kwargs) -> BrushStroke:
        """創建畫筆筆觸記錄。"""
        stroke = BrushStroke(pdf_id=pdf_id, **kwargs)
        db.add(stroke)
        db.commit()
        db.refresh(stroke)
        return stroke

    @staticmethod
    def create_brush_strokes_batch(db: Session, pdf_id: int, strokes_data: List[Dict[str, Any]]) -> List[BrushStroke]:
        """批量創建畫筆筆觸記錄。"""
        strokes = []
        for data in strokes_data:
            stroke = BrushStroke(pdf_id=pdf_id, **data)
            db.add(stroke)
            strokes.append(stroke)
        db.commit()
        for s in strokes:
            db.refresh(s)
        return strokes

    @staticmethod
    def get_brush_strokes_by_pdf(db: Session, pdf_id: int) -> List[BrushStroke]:
        """獲取 PDF 文件的所有筆觸。"""
        return db.query(BrushStroke).filter(
            BrushStroke.pdf_id == pdf_id
        ).order_by(BrushStroke.created_at.asc()).all()

    @staticmethod
    def get_brush_strokes_by_page(db: Session, pdf_id: int, page_number: int) -> List[BrushStroke]:
        """獲取 PDF 指定頁面的筆觸。"""
        return db.query(BrushStroke).filter(
            BrushStroke.pdf_id == pdf_id,
            BrushStroke.page_number == page_number
        ).order_by(BrushStroke.created_at.asc()).all()

    @staticmethod
    def delete_brush_stroke(db: Session, stroke_id: int) -> bool:
        """刪除單一筆觸。"""
        stroke = db.query(BrushStroke).filter(BrushStroke.id == stroke_id).first()
        if stroke:
            db.delete(stroke)
            db.commit()
            return True
        return False

    @staticmethod
    def delete_brush_strokes_by_page(db: Session, pdf_id: int, page_number: int) -> int:
        """刪除指定頁面的所有筆觸，返回刪除數量。"""
        count = db.query(BrushStroke).filter(
            BrushStroke.pdf_id == pdf_id,
            BrushStroke.page_number == page_number
        ).delete()
        db.commit()
        return count

    # ============ PageImage Operations ============
    @staticmethod
    def create_page_image(db: Session, pdf_id: int, **kwargs) -> PageImage:
        """創建頁面圖片記錄。"""
        img = PageImage(pdf_id=pdf_id, **kwargs)
        db.add(img)
        db.commit()
        db.refresh(img)
        return img

    @staticmethod
    def get_page_images_by_page(db: Session, pdf_id: int, page_number: int) -> List[PageImage]:
        """獲取 PDF 指定頁面的所有圖片。"""
        return db.query(PageImage).filter(
            PageImage.pdf_id == pdf_id,
            PageImage.page_number == page_number
        ).order_by(PageImage.created_at.asc()).all()

    @staticmethod
    def get_page_images_by_pdf(db: Session, pdf_id: int) -> List[PageImage]:
        """獲取 PDF 所有頁面的圖片。"""
        return db.query(PageImage).filter(
            PageImage.pdf_id == pdf_id
        ).order_by(PageImage.created_at.asc()).all()

    @staticmethod
    def update_page_image(db: Session, image_id: int, **kwargs) -> Optional[PageImage]:
        """更新圖片位置/尺寸。"""
        img = db.query(PageImage).filter(PageImage.id == image_id).first()
        if img:
            for key, value in kwargs.items():
                if hasattr(img, key):
                    setattr(img, key, value)
            db.commit()
            db.refresh(img)
        return img

    @staticmethod
    def delete_page_image(db: Session, image_id: int) -> bool:
        """刪除單一圖片。"""
        img = db.query(PageImage).filter(PageImage.id == image_id).first()
        if img:
            db.delete(img)
            db.commit()
            return True
        return False
