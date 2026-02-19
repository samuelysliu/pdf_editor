"""FastAPI 主應用程序。"""
from dotenv import load_dotenv
load_dotenv()  # 讀取 .env 檔

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from modules.db_init import Base
from modules.db_connect import engine
from controls.pdf_api import router as pdf_router
from controls.auth_api import router as auth_router
from controls.payment_api import router as payment_router

# 創建所有數據庫表
Base.metadata.create_all(bind=engine)

# 創建 FastAPI 應用
app = FastAPI(
    title="PDF Editor API",
    description="一個支援額度系統和 Google Play 支付的 PDF 編輯器 API",
    version="1.0.0"
)

# CORS 配置
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注冊路由
app.include_router(auth_router)
app.include_router(pdf_router)
app.include_router(payment_router)


@app.get("/")
def read_root():
    """根路由。"""
    return {
        "message": "歡迎使用 PDF 編輯器 API",
        "docs": "/docs",
        "openapi": "/openapi.json"
    }


@app.get("/health")
def health_check():
    """健康檢查端點。"""
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
