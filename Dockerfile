FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PORT=8000
EXPOSE 8000
# One process (256 MB machine), four request threads: a slow request or a
# stalled client no longer queues every other caller behind it. src/db.py
# gives each thread its own connection.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--worker-class", "gthread", "--threads", "4", "--timeout", "120", "api:app"]
