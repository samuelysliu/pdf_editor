"""FastAPI routes for PDF Editor operations."""
import os
from fastapi import APIRouter, Depends, HTTPException, status, Header, UploadFile, File, Form
from fastapi.responses import Response
from sqlalchemy.orm import Session
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field
from io import BytesIO
from PyPDF2 import PdfReader
import fitz  # PyMuPDF

from modules.db_connect import get_db
from modules.pdf_crud import PDFEditorCRUD
from controls.pdf_service import PDFEditorService
from controls.tools import verify_token

router = APIRouter(prefix="/api/pdf", tags=["PDF Editor"])


# Pydantic Models
# 畫筆筆觸請求模型
class BrushStrokeRequest(BaseModel):
    pdf_id: int
    page_number: int = Field(..., ge=1, description="頁碼（從 1 開始）")
    color: str = Field(default="#000000", description="筆觸顏色（hex）")
    width: float = Field(default=2.0, gt=0, description="筆觸寬度")
    opacity: float = Field(default=1.0, ge=0, le=1, description="透明度 0~1")
    tool: str = Field(default="pen", description="工具類型：pen / highlighter / eraser")
    points: List[Dict[str, float]] = Field(..., description="座標點 [{x, y}, ...]")

# 批量保存筆觸請求
class BrushStrokeBatchRequest(BaseModel):
    pdf_id: int
    strokes: List[BrushStrokeRequest]

# 合併 PDF 請求模型
class MergePDFRequest(BaseModel):
    pdf_ids: list[int]
    output_filename: str

# 轉 Word 請求模型
class ConvertToWordRequest(BaseModel):
    pdf_id: int
    output_filename: str


def get_user_id(authorization: Optional[str] = Header(None)) -> int:
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

# 上傳 PDF 文件並扣除額度。
@router.post("/upload", response_model=Dict[str, Any])
async def upload_pdf(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    邏輯：
    - 檢查並扣除用戶額度
    - 根據 PDF 頁數計算扣除額度
    
    Args:
        file: 上傳的 PDF 文件
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        Dict: 上傳結果和額度信息
        
    Raises:
        HTTPException(402): 額度不足
        HTTPException(400): 文件無效
        HTTPException(401): 未授權
        HTTPException(500): 伺服器錯誤
    """
    try:
        # 讀取文件內容
        contents = await file.read()
        file_size = len(contents)
        
        # 驗證文件格式
        if not file.filename.lower().endswith('.pdf'):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only PDF files are allowed"
            )
        
        # 使用 PyPDF2 讀取真實頁數
        try:
            pdf_reader = PdfReader(BytesIO(contents))
            page_count = len(pdf_reader.pages)
        except Exception as pdf_error:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid PDF file: {str(pdf_error)}"
            )
        
        # 驗證 PDF 不為空
        if page_count == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="PDF file is empty"
            )
        
        # 文件保存路徑
        file_path = f"uploads/{user_id}/{file.filename}"
        
        # 確保目錄存在並將文件寫入磁碟
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, "wb") as f:
            f.write(contents)
        
        # 處理上傳並扣除額度
        result = PDFEditorService.upload_pdf(
            db,
            user_id,
            filename=file.filename,
            file_path=file_path,
            file_size=file_size,
            page_count=page_count
        )
        
        if not result["success"]:
            # 額度不足返回 402
            raise HTTPException(
                status_code=status.HTTP_402_PAYMENT_REQUIRED,
                detail=result["message"]
            )
        
        return {
            "success": True,
            "message": "PDF uploaded and quota deducted",
            "data": result
        }
    
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )

# 獲取 PDF 指定頁面的渲染圖片（PNG）
@router.get("/page-image/{pdf_id}/{page_number}")
def get_pdf_page_image(
    pdf_id: int,
    page_number: int,
    dpi: int = 150,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
):
    """
    將 PDF 的某一頁渲染為 PNG 圖片返回。

    Args:
        pdf_id: PDF 文件 ID
        page_number: 頁碼（從 1 開始）
        dpi: 渲染解析度（預設 150）
        db: 數據庫會話
        user_id: 用戶 ID

    Returns:
        PNG 圖片二進位資料
    """
    try:
        pdf_record = PDFEditorCRUD.get_pdf_file(db, pdf_id, user_id)
        if not pdf_record:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found or access denied"
            )

        if page_number < 1 or page_number > pdf_record.page_count:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid page number. Must be 1~{pdf_record.page_count}"
            )

        if not os.path.exists(pdf_record.file_path):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file missing on disk"
            )

        # 使用 PyMuPDF 渲染頁面為 PNG
        doc = fitz.open(pdf_record.file_path)
        page = doc.load_page(page_number - 1)  # 0-indexed
        zoom = dpi / 72
        mat = fitz.Matrix(zoom, zoom)
        pix = page.get_pixmap(matrix=mat)
        png_bytes = pix.tobytes("png")
        doc.close()

        return Response(content=png_bytes, media_type="image/png")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# 獲取用戶的 PDF 文件列表。
@router.get("/list", response_model=Dict[str, Any])
def get_pdf_files(
    limit: int = 50,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    Args:
        limit: 返回的最大文件數
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        用戶的 PDF 文件列表
    """
    try:
        result = PDFEditorService.get_pdf_files(db, user_id, limit)
        return result
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

#  獲取用戶當前的額度狀態。
@router.get("/quota", response_model=Dict[str, Any])
def get_quota_status(
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    Args:
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        額度狀態信息
    """
    try:
        quota_status = PDFEditorService.get_quota_status(db, user_id)
        return {
            "success": True,
            "data": quota_status
        }
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 在 PDF 頁面插入圖片（上傳圖片檔案）。
@router.post("/insert-image", response_model=Dict[str, Any])
async def insert_image(
    file: UploadFile = File(...),
    pdf_id: int = Form(...),
    page_number: int = Form(...),
    x: float = Form(0.0),
    y: float = Form(0.0),
    img_width: float = Form(200.0),
    img_height: float = Form(200.0),
    rotation: float = Form(0.0),
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    上傳圖片並插入到 PDF 指定頁面的指定位置。
    座標使用 150 DPI 圖片像素空間（與前端筆觸座標一致）。

    Args:
        file: 圖片檔案（png/jpg/jpeg/gif）
        pdf_id: PDF 文件 ID
        page_number: 頁碼（從 1 開始）
        x, y: 圖片左上角座標（150 DPI image space）
        img_width, img_height: 圖片顯示尺寸（150 DPI image space）
        rotation: 旋轉角度（度，順時針）
    """
    try:
        # 驗證 PDF 存在且屬於該用戶
        pdf = PDFEditorCRUD.get_pdf_file(db, pdf_id, user_id)
        if not pdf:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found or access denied"
            )

        if page_number < 1 or page_number > pdf.page_count:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid page number. Must be 1~{pdf.page_count}"
            )

        # 驗證檔案格式
        allowed_ext = ('.png', '.jpg', '.jpeg', '.gif', '.webp')
        if not file.filename.lower().endswith(allowed_ext):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Only image files are allowed: {', '.join(allowed_ext)}"
            )

        # 讀取並保存圖片
        contents = await file.read()
        image_dir = f"uploads/{user_id}/images"
        os.makedirs(image_dir, exist_ok=True)

        import uuid
        ext = os.path.splitext(file.filename)[1]
        image_filename = f"{uuid.uuid4().hex}{ext}"
        image_path = os.path.join(image_dir, image_filename)

        with open(image_path, "wb") as f:
            f.write(contents)

        # 存入資料庫
        page_image = PDFEditorCRUD.create_page_image(
            db, pdf_id,
            page_number=page_number,
            image_path=image_path,
            x=x,
            y=y,
            img_width=img_width,
            img_height=img_height,
            rotation=rotation,
        )

        return {
            "success": True,
            "message": "Image inserted successfully",
            "data": {
                "image_id": page_image.id,
                "pdf_id": pdf_id,
                "page_number": page_number,
                "x": page_image.x,
                "y": page_image.y,
                "img_width": page_image.img_width,
                "img_height": page_image.img_height,
                "rotation": page_image.rotation,
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# 取得 PDF 指定頁面的所有插入圖片
@router.get("/page-images/{pdf_id}", response_model=Dict[str, Any])
def get_page_images(
    pdf_id: int,
    page_number: Optional[int] = None,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    try:
        pdf = PDFEditorCRUD.get_pdf_file(db, pdf_id, user_id)
        if not pdf:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found or access denied"
            )

        if page_number is not None:
            images = PDFEditorCRUD.get_page_images_by_page(db, pdf_id, page_number)
        else:
            images = PDFEditorCRUD.get_page_images_by_pdf(db, pdf_id)

        return {
            "success": True,
            "data": {
                "pdf_id": pdf_id,
                "image_count": len(images),
                "images": [
                    {
                        "image_id": img.id,
                        "page_number": img.page_number,
                        "x": img.x,
                        "y": img.y,
                        "img_width": img.img_width,
                        "img_height": img.img_height,
                        "rotation": img.rotation,
                    }
                    for img in images
                ]
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# 取得已插入圖片的原始檔案
@router.get("/page-image-file/{image_id}")
def get_page_image_file(
    image_id: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
):
    try:
        from modules.db_init import PageImage
        img = db.query(PageImage).filter(PageImage.id == image_id).first()
        if not img:
            raise HTTPException(status_code=404, detail="Image not found")

        # 驗證該圖片對應的 PDF 屬於此用戶
        pdf = PDFEditorCRUD.get_pdf_file(db, img.pdf_id, user_id)
        if not pdf:
            raise HTTPException(status_code=404, detail="Access denied")

        if not os.path.exists(img.image_path):
            raise HTTPException(status_code=404, detail="Image file missing on disk")

        with open(img.image_path, "rb") as f:
            data = f.read()

        ext = os.path.splitext(img.image_path)[1].lower()
        media_types = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp'}
        media_type = media_types.get(ext, 'application/octet-stream')

        return Response(content=data, media_type=media_type)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# 更新圖片位置/尺寸/旋轉
@router.put("/page-image/{image_id}", response_model=Dict[str, Any])
def update_page_image(
    image_id: int,
    x: float = 0.0,
    y: float = 0.0,
    img_width: float = 200.0,
    img_height: float = 200.0,
    rotation: float = 0.0,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    try:
        from modules.db_init import PageImage
        img = db.query(PageImage).filter(PageImage.id == image_id).first()
        if not img:
            raise HTTPException(status_code=404, detail="Image not found")

        pdf = PDFEditorCRUD.get_pdf_file(db, img.pdf_id, user_id)
        if not pdf:
            raise HTTPException(status_code=404, detail="Access denied")

        updated = PDFEditorCRUD.update_page_image(
            db, image_id, x=x, y=y, img_width=img_width, img_height=img_height, rotation=rotation
        )

        return {
            "success": True,
            "message": "Image updated",
            "data": {
                "image_id": updated.id,
                "x": updated.x,
                "y": updated.y,
                "img_width": updated.img_width,
                "img_height": updated.img_height,
                "rotation": updated.rotation,
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# 刪除插入的圖片
@router.delete("/page-image/{image_id}", response_model=Dict[str, Any])
def delete_page_image(
    image_id: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    try:
        from modules.db_init import PageImage
        img = db.query(PageImage).filter(PageImage.id == image_id).first()
        if not img:
            raise HTTPException(status_code=404, detail="Image not found")

        pdf = PDFEditorCRUD.get_pdf_file(db, img.pdf_id, user_id)
        if not pdf:
            raise HTTPException(status_code=404, detail="Access denied")

        # 刪除磁碟上的圖片
        if os.path.exists(img.image_path):
            os.remove(img.image_path)

        PDFEditorCRUD.delete_page_image(db, image_id)

        return {
            "success": True,
            "message": "Image deleted",
            "data": {"image_id": image_id}
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# 保存單一畫筆筆觸到資料庫。
@router.post("/brush-save", response_model=Dict[str, Any])
def save_brush_stroke(
    request: BrushStrokeRequest,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    前端每完成一筆繪製後即時傳送，後端持久化保存。
    
    Args:
        request: 畫筆筆觸請求（pdf_id, page_number, color, width, opacity, tool, points）
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        保存結果，包含筆觸 ID
    """
    try:
        # 驗證 PDF 存在且屬於該用戶
        pdf = PDFEditorCRUD.get_pdf_file(db, request.pdf_id, user_id)
        if not pdf:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found or access denied"
            )
        
        # 驗證頁碼範圍
        if request.page_number > pdf.page_count:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Page number {request.page_number} exceeds total pages ({pdf.page_count})"
            )
        
        # 保存筆觸
        stroke = PDFEditorCRUD.create_brush_stroke(
            db,
            pdf_id=request.pdf_id,
            page_number=request.page_number,
            color=request.color,
            width=request.width,
            opacity=request.opacity,
            tool=request.tool,
            points=request.points
        )
        
        return {
            "success": True,
            "message": "Brush stroke saved successfully",
            "data": {
                "stroke_id": stroke.id,
                "pdf_id": stroke.pdf_id,
                "page_number": stroke.page_number,
                "tool": stroke.tool,
                "points_count": len(stroke.points),
                "created_at": str(stroke.created_at)
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 批量保存畫筆筆觸（適用於離線同步或一次性提交多筆繪製）。
@router.post("/brush-save-batch", response_model=Dict[str, Any])
def save_brush_strokes_batch(
    request: BrushStrokeBatchRequest,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    Args:
        request: 批量請求（pdf_id, strokes[]）
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        批量保存結果
    """
    try:
        pdf = PDFEditorCRUD.get_pdf_file(db, request.pdf_id, user_id)
        if not pdf:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found or access denied"
            )
        
        strokes_data = [
            {
                "page_number": s.page_number,
                "color": s.color,
                "width": s.width,
                "opacity": s.opacity,
                "tool": s.tool,
                "points": s.points
            }
            for s in request.strokes
        ]
        
        saved = PDFEditorCRUD.create_brush_strokes_batch(db, request.pdf_id, strokes_data)
        
        return {
            "success": True,
            "message": f"{len(saved)} brush strokes saved",
            "data": {
                "pdf_id": request.pdf_id,
                "saved_count": len(saved),
                "stroke_ids": [s.id for s in saved]
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 獲取 PDF 的畫筆筆觸。
@router.get("/brush-strokes/{pdf_id}", response_model=Dict[str, Any])
def get_brush_strokes(
    pdf_id: int,
    page_number: Optional[int] = None,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    可選按頁碼過濾。
    
    Args:
        pdf_id: PDF 文件 ID
        page_number: 頁碼（可選，不傳則返回所有頁的筆觸）
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        筆觸列表
    """
    try:
        pdf = PDFEditorCRUD.get_pdf_file(db, pdf_id, user_id)
        if not pdf:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found or access denied"
            )
        
        if page_number is not None:
            strokes = PDFEditorCRUD.get_brush_strokes_by_page(db, pdf_id, page_number)
        else:
            strokes = PDFEditorCRUD.get_brush_strokes_by_pdf(db, pdf_id)
        
        return {
            "success": True,
            "data": {
                "pdf_id": pdf_id,
                "stroke_count": len(strokes),
                "strokes": [
                    {
                        "stroke_id": s.id,
                        "page_number": s.page_number,
                        "color": s.color,
                        "width": s.width,
                        "opacity": s.opacity,
                        "tool": s.tool,
                        "points": s.points,
                        "created_at": str(s.created_at)
                    }
                    for s in strokes
                ]
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 刪除單一畫筆筆觸
@router.delete("/brush-stroke/{stroke_id}", response_model=Dict[str, Any])
def delete_brush_stroke(
    stroke_id: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """    
    Args:
        stroke_id: 筆觸 ID
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        刪除結果
    """
    try:
        success = PDFEditorCRUD.delete_brush_stroke(db, stroke_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Brush stroke not found"
            )
        
        return {
            "success": True,
            "message": "Brush stroke deleted",
            "data": {"stroke_id": stroke_id}
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 清除指定頁面的所有筆觸。
@router.delete("/brush-strokes/{pdf_id}/page/{page_number}", response_model=Dict[str, Any])
def clear_page_brush_strokes(
    pdf_id: int,
    page_number: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    
    
    Args:
        pdf_id: PDF 文件 ID
        page_number: 頁碼
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        清除結果
    """
    try:
        pdf = PDFEditorCRUD.get_pdf_file(db, pdf_id, user_id)
        if not pdf:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found or access denied"
            )
        
        deleted_count = PDFEditorCRUD.delete_brush_strokes_by_page(db, pdf_id, page_number)
        
        return {
            "success": True,
            "message": f"{deleted_count} brush strokes cleared from page {page_number}",
            "data": {
                "pdf_id": pdf_id,
                "page_number": page_number,
                "deleted_count": deleted_count
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 合併多個 PDF 文件。
@router.post("/merge", response_model=Dict[str, Any])
def merge_pdfs(
    request: MergePDFRequest,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    Args:
        request: 合併請求（pdf_ids, output_filename）
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        合併結果，包含新文件的 ID、檔名、頁數等資訊
        
    Raises:
        HTTPException(400): PDF 數量不足或參數錯誤
        HTTPException(404): PDF 文件不存在或不屬於該用戶
        HTTPException(500): 合併過程發生錯誤
    """
    try:
        result = PDFEditorService.merge_pdfs(
            db,
            user_id,
            pdf_ids=request.pdf_ids,
            output_filename=request.output_filename
        )
        
        return {
            "success": True,
            "message": result["message"],
            "data": result
        }
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# 將 PDF 轉換為 Word 文檔。
@router.get("/convert-to-word/{pdf_id}")
def convert_to_word(
    pdf_id: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
):
    """
    將 PDF 轉換為 Word（DOCX）並回傳二進位檔案供下載。

    Args:
        pdf_id: PDF 文件 ID
        db: 數據庫會話
        user_id: 用戶 ID

    Returns:
        DOCX 二進位資料
    """
    try:
        from pdf2docx import Converter
        import tempfile

        pdf_record = PDFEditorCRUD.get_pdf_file(db, pdf_id, user_id)
        if not pdf_record:
            raise HTTPException(status_code=404, detail="PDF not found")

        pdf_path = pdf_record.file_path
        if not os.path.exists(pdf_path):
            raise HTTPException(status_code=404, detail="PDF file not found on disk")

        # 在暫存目錄轉換
        with tempfile.TemporaryDirectory() as tmp_dir:
            docx_path = os.path.join(tmp_dir, "output.docx")
            cv = Converter(pdf_path)
            cv.convert(docx_path)
            cv.close()

            with open(docx_path, "rb") as f:
                docx_bytes = f.read()

        # 產生檔名
        original_name = os.path.splitext(pdf_record.filename)[0]
        output_filename = f"{original_name}.docx"

        return Response(
            content=docx_bytes,
            media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            headers={
                "Content-Disposition": f'attachment; filename="{output_filename}"'
            },
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"轉換失敗：{str(e)}")


# 下載編輯後的 PDF（將筆觸渲染到 PDF 上）
@router.get("/download/{pdf_id}")
def download_pdf(
    pdf_id: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
):
    """
    將所有頁面的筆觸渲染（flatten）到原始 PDF 上，
    返回最終合成的 PDF 檔案供下載。

    Args:
        pdf_id: PDF 文件 ID
        db: 數據庫會話
        user_id: 用戶 ID

    Returns:
        PDF 二進位資料（application/pdf）
    """
    try:
        pdf_record = PDFEditorCRUD.get_pdf_file(db, pdf_id, user_id)
        if not pdf_record:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found or access denied"
            )

        if not os.path.exists(pdf_record.file_path):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file missing on disk"
            )

        # 取得該 PDF 所有筆觸
        all_strokes = PDFEditorCRUD.get_brush_strokes_by_pdf(db, pdf_id)

        # 按頁碼分組
        strokes_by_page: Dict[int, list] = {}
        for s in all_strokes:
            strokes_by_page.setdefault(s.page_number, []).append(s)

        # 取得該 PDF 所有插入圖片
        all_page_images = PDFEditorCRUD.get_page_images_by_pdf(db, pdf_id)
        images_by_page: Dict[int, list] = {}
        for img in all_page_images:
            images_by_page.setdefault(img.page_number, []).append(img)

        # 用 PyMuPDF 開啟 PDF 並在每頁上繪製圖片與筆觸
        doc = fitz.open(pdf_record.file_path)

        for page_num in range(len(doc)):
            page = doc[page_num]

            # ─── 先渲染插入的圖片 ───
            page_images = images_by_page.get(page_num + 1, [])
            render_zoom = 150.0 / 72.0
            scale = 1.0 / render_zoom

            for img in page_images:
                if not os.path.exists(img.image_path):
                    continue
                # 將 150 DPI image-space 座標轉為 PDF points
                x0 = img.x * scale
                y0 = img.y * scale
                x1 = x0 + img.img_width * scale
                y1 = y0 + img.img_height * scale
                rect = fitz.Rect(x0, y0, x1, y1)

                # 支援旋轉：讀取圖片 → 旋轉 → 插入 pixmap
                rotation_deg = getattr(img, 'rotation', 0.0) or 0.0
                if abs(rotation_deg) > 0.1:
                    import math
                    from PIL import Image as PILImage
                    pil_img = PILImage.open(img.image_path).convert("RGBA")
                    pil_img = pil_img.rotate(-rotation_deg, expand=True, resample=PILImage.BICUBIC)
                    # 轉為 PNG bytes 再插入
                    from io import BytesIO as _BytesIO
                    buf = _BytesIO()
                    pil_img.save(buf, format="PNG")
                    page.insert_image(rect, stream=buf.getvalue())
                else:
                    page.insert_image(rect, filename=img.image_path)

            # ─── 再渲染筆觸 ───
            page_strokes = strokes_by_page.get(page_num + 1, [])

            if not page_strokes:
                continue

            # render_zoom / scale 已在上方計算

            for stroke in page_strokes:
                points = stroke.points  # list of {x, y}
                if not points or len(points) < 2:
                    continue

                # 解析顏色
                color_hex = stroke.color.lstrip('#')
                if len(color_hex) == 6:
                    r = int(color_hex[0:2], 16) / 255.0
                    g = int(color_hex[2:4], 16) / 255.0
                    b = int(color_hex[4:6], 16) / 255.0
                else:
                    r, g, b = 0, 0, 0

                color = (r, g, b)
                width = stroke.width * scale
                opacity = stroke.opacity

                # eraser 用白色
                if stroke.tool == 'eraser':
                    color = (1, 1, 1)
                    opacity = 1.0

                # 在頁面上繪製路徑
                shape = page.new_shape()
                first_pt = fitz.Point(points[0]['x'] * scale, points[0]['y'] * scale)
                shape.draw_line(first_pt, first_pt)  # move to

                for i in range(1, len(points)):
                    pt_from = fitz.Point(points[i - 1]['x'] * scale, points[i - 1]['y'] * scale)
                    pt_to = fitz.Point(points[i]['x'] * scale, points[i]['y'] * scale)
                    shape.draw_line(pt_from, pt_to)

                shape.finish(
                    color=color,
                    width=width,
                    stroke_opacity=opacity,
                    lineCap=1,   # round cap
                    lineJoin=1,  # round join
                )
                shape.commit()

        # 導出 PDF
        pdf_bytes = doc.tobytes()
        doc.close()

        # 設定下載檔名
        download_name = pdf_record.filename
        if not download_name.lower().endswith('.pdf'):
            download_name += '.pdf'

        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={
                "Content-Disposition": f'attachment; filename="{download_name}"'
            }
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# 刪除 PDF 文件。
@router.delete("/delete/{pdf_id}", response_model=Dict[str, Any])
def delete_pdf(
    pdf_id: int,
    db: Session = Depends(get_db),
    user_id: int = Depends(get_user_id)
) -> Dict[str, Any]:
    """
    Args:
        pdf_id: PDF 文件 ID
        db: 數據庫會話
        user_id: 用戶ID
    
    Returns:
        刪除結果
    """
    try:
        success = PDFEditorCRUD.delete_pdf_file(db, pdf_id, user_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="PDF file not found"
            )
        
        return {
            "success": True,
            "message": "PDF deleted successfully",
            "data": {"pdf_id": pdf_id}
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
