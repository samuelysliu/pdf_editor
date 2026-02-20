"""Database connection and session management."""
import os
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from sqlalchemy.orm import sessionmaker, Session

# PostgreSQL 連線設定
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_NAME = os.getenv("DB_NAME")

# Cloud Run 透過 Unix socket 連線 Cloud SQL（無需 Auth Proxy）
# 本地開發透過 TCP 連線（需先啟動 Auth Proxy）
CLOUD_SQL_CONNECTION_NAME = os.getenv("CLOUD_SQL_CONNECTION_NAME", "")
DB_SOCKET_DIR = os.getenv("DB_SOCKET_DIR", "/cloudsql")

if CLOUD_SQL_CONNECTION_NAME:
    # Cloud Run：透過 Unix socket
    DATABASE_URL = URL.create(
        drivername="postgresql",
        username=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        query={"host": f"{DB_SOCKET_DIR}/{CLOUD_SQL_CONNECTION_NAME}"},
    )
else:
    # 本地開發：透過 TCP (Auth Proxy)
    DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
    DB_PORT = os.getenv("DB_PORT", "5433")
    DATABASE_URL = URL.create(
        drivername="postgresql",
        username=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=int(DB_PORT),
        database=DB_NAME,
    )

engine = create_engine(DATABASE_URL, pool_pre_ping=True)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db() -> Session:
    """依賴注入：獲取 DB session。"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
