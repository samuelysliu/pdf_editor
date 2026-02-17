"""Database models using SQLAlchemy ORM."""
from sqlalchemy import Column, Integer, String, BigInteger, Float, DateTime, Text, ForeignKey, JSON, func
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship

Base = declarative_base()


class User(Base):
    """用戶基本信息模型。"""
    __tablename__ = "users"

    uid = Column(Integer, primary_key=True, index=True, autoincrement=True)
    username = Column(String(50), unique=True, nullable=False, index=True)
    email = Column(String(100), unique=True, nullable=False)
    password_hash = Column(String(255), nullable=False)

    # 額度系統（統一額度）
    quota = Column(Integer, default=5, nullable=False)  # 可用額度餘額（頁數）

    # 時間戳
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, onupdate=func.now())

    # 關係
    transactions = relationship("Transaction", back_populates="user", cascade="all, delete-orphan")
    pdf_files = relationship("PDFFile", back_populates="user", cascade="all, delete-orphan")


class PDFFile(Base):
    """用戶上傳的 PDF 文件。"""
    __tablename__ = "pdf_files"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.uid"), nullable=False, index=True)

    # 文件信息
    filename = Column(String(255), nullable=False)
    file_path = Column(String(512), nullable=False)  # 存儲路徑
    file_size = Column(BigInteger, nullable=False)  # 文件大小（字節）

    # 頁數統計
    page_count = Column(Integer, default=0, nullable=False)  # 總頁數
    quota_used = Column(Integer, default=0, nullable=False)  # 消耗的額度（頁數）

    # 時間戳
    created_at = Column(DateTime, server_default=func.now(), nullable=False)
    updated_at = Column(DateTime, onupdate=func.now())

    # 關係
    user = relationship("User", back_populates="pdf_files")
    brush_strokes = relationship("BrushStroke", back_populates="pdf_file", cascade="all, delete-orphan")
    page_images = relationship("PageImage", back_populates="pdf_file", cascade="all, delete-orphan")


class BrushStroke(Base):
    """PDF 上的畫筆筆觸記錄。

    用途：
    - 保留原始向量數據，支援 undo/redo 和跨設備同步
    - 前端以 JSON 傳入完整筆觸路徑，後端持久化
    - 導出 PDF 時再將筆觸渲染（flatten）到最終文件
    """
    __tablename__ = "brush_strokes"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    pdf_id = Column(Integer, ForeignKey("pdf_files.id"), nullable=False, index=True)
    page_number = Column(Integer, nullable=False)  # 筆觸所在頁碼（從 1 開始）

    # 筆觸樣式
    color = Column(String(20), default="#000000", nullable=False)  # 顏色（hex）
    width = Column(Float, default=2.0, nullable=False)  # 線寬（px）
    opacity = Column(Float, default=1.0, nullable=False)  # 不透明度 0.0~1.0
    tool = Column(String(20), default="pen", nullable=False)  # 工具類型：pen | highlighter | eraser

    # 筆觸路徑（JSON 陣列）
    # 格式：[{"x": 10.5, "y": 20.3}, {"x": 11.0, "y": 21.5}, ...]
    points = Column(JSON, nullable=False)

    # 時間戳
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    # 關係
    pdf_file = relationship("PDFFile", back_populates="brush_strokes")


class PageImage(Base):
    """插入到 PDF 頁面的圖片記錄。

    座標系說明：
    - x, y, width, height 均為 150 DPI 圖片像素座標（與筆觸相同）
    - 後端下載時會轉換回 PDF 點座標
    """
    __tablename__ = "page_images"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    pdf_id = Column(Integer, ForeignKey("pdf_files.id"), nullable=False, index=True)
    page_number = Column(Integer, nullable=False)  # 所在頁碼（從 1 開始）

    # 圖片檔案
    image_path = Column(String(512), nullable=False)  # 儲存路徑

    # 位置與尺寸（150 DPI 圖片像素座標）
    x = Column(Float, default=0.0, nullable=False)
    y = Column(Float, default=0.0, nullable=False)
    img_width = Column(Float, default=200.0, nullable=False)
    img_height = Column(Float, default=200.0, nullable=False)

    # 旋轉角度（度，順時針，0~360）
    rotation = Column(Float, default=0.0, nullable=False)

    # 時間戳
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    # 關係
    pdf_file = relationship("PDFFile", back_populates="page_images")


class Transaction(Base):
    """Google Play 交易記錄。"""
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.uid"), nullable=False, index=True)

    # 交易信息
    transaction_id = Column(String(255), unique=True, nullable=False, index=True)  # Google Play transaction ID
    product_id = Column(String(100), nullable=False)  # 商品 ID

    # 金額和額度
    amount = Column(BigInteger, nullable=False)  # 金額（美分，例如 999 = $9.99）
    quota_added = Column(Integer, nullable=False)  # 新增額度（頁數）

    # 狀態
    status = Column(String(20), default="completed", nullable=False)  # "pending" | "completed" | "failed"
    receipt_data = Column(Text, nullable=True)  # Google Play 收據數據

    # 時間戳
    created_at = Column(DateTime, server_default=func.now(), nullable=False)

    # 關係
    user = relationship("User", back_populates="transactions")
