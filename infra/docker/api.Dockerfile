# The API and the projector run from one image: same code, different command.
FROM python:3.12-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Dependencies first, pinned by the same file the local environment uses, so a
# deployment cannot quietly resolve a different version than the tests ran on.
COPY services/api/pyproject.toml ./pyproject.toml
RUN pip install --no-cache-dir \
      "alembic==1.18.5" \
      "argon2-cffi==25.1.0" \
      "asyncpg==0.31.0" \
      "email-validator==2.3.0" \
      "fastapi==0.140.0" \
      "pydantic==2.13.4" \
      "PyJWT==2.13.0" \
      "SQLAlchemy[asyncio]==2.0.51" \
      "tzdata==2026.3" \
      "uvicorn==0.51.0"

COPY services/api/src ./src
COPY services/api/migrations ./migrations
COPY services/api/alembic.ini ./alembic.ini

ENV PYTHONPATH=/app/src

# Never root: a container that only serves HTTP has no business owning its own
# filesystem.
RUN useradd --system --uid 10001 --create-home mfa
USER mfa

EXPOSE 8000
CMD ["python", "-m", "uvicorn", "mobile_finance_api.runtime:app", \
     "--host", "0.0.0.0", "--port", "8000"]
