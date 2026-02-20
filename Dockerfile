# ---- Build Stage ----
FROM python:3.11-slim AS builder

WORKDIR /app

# 系統依賴
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

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /install /usr/local

COPY main.py .
COPY create_db.py .
COPY controls/ controls/
COPY modules/ modules/

RUN mkdir -p uploads

# Service Account Key
COPY project-c02ae071-e5c5-4fc4-9dc-29a1f42dbaea.json .

# Cloud Run 會自動設定 PORT 環境變數，預設為 8080
ENV PORT=8080

EXPOSE ${PORT}

# 啟動命令
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT} --workers 1
