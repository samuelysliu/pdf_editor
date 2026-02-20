# ---- Build Stage ----
FROM python:3.11-slim AS builder

WORKDIR /app

# 系統依賴（PyMuPDF、Pillow、psycopg2 編譯需要）
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Runtime Stage ----
FROM python:3.11-slim

WORKDIR /app

# 執行期只需 libpq（PostgreSQL client library）
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# 複製安裝好的 Python 套件
COPY --from=builder /install /usr/local

# 複製應用程式碼
COPY main.py .
COPY create_db.py .
COPY controls/ controls/
COPY modules/ modules/

# 建立上傳目錄
RUN mkdir -p uploads

# Service Account Key（如果有的話，部署時透過 Secret Manager 或環境變數掛入）
# COPY project-c02ae071-e5c5-4fc4-9dc-29a1f42dbaea.json .

# Cloud Run 會注入 PORT 環境變數（預設 8080）
ENV PORT=8080

EXPOSE ${PORT}

# 啟動 FastAPI（Cloud Run 要求監聽 0.0.0.0:$PORT）
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT} --workers 1
