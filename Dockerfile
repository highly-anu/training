FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PORT=8000
# Answer every reference route (philosophies, archetypes, exercises, Explore's
# documents…) now, from the packages in this image, so the 256 MB worker serves
# bytes instead of parsing every package per request (api.static_json).
ENV STATIC_BUILD_DIR=/app/static_build
RUN SUPABASE_URL= DATABASE_URL= python tools/build_static_cache.py "$STATIC_BUILD_DIR"
EXPOSE 8000
# One process (256 MB machine), four request threads: a slow request or a
# stalled client no longer queues every other caller behind it. src/db.py
# gives each thread its own connection.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--worker-class", "gthread", "--threads", "4", "--timeout", "120", "api:app"]
