# The API and the projector run from one image: same code, different command.
FROM python:3.12-slim@sha256:aa943ce411423c7582288f18707ff66eddcbaeb510502d747a72aeb34f30d159 AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Dependencies come from uv.lock, hashes and transitive packages included, which
# is what CI tests. A deployment cannot resolve a different version from the
# ones that ran. uv only reads the lock and does not stay in the image.
COPY services/api/pyproject.toml services/api/uv.lock ./
RUN pip install --quiet "uv==0.11.32" \
    && uv export --no-cache --frozen --no-dev --no-emit-project \
         --format requirements-txt --output-file /tmp/requirements.txt \
    && pip install --no-deps --require-hashes -r /tmp/requirements.txt \
    && pip uninstall --yes uv \
    && rm /tmp/requirements.txt

COPY services/api/src ./src
COPY services/api/migrations ./migrations
COPY services/api/alembic.ini ./alembic.ini

ENV PYTHONPATH=/app/src

# Never root: a container that only serves HTTP has no business owning its own
# filesystem.
RUN useradd --system --uid 10001 --create-home mfa
USER mfa

EXPOSE 8000
# No access log here: Caddy already keeps one, and it leaves out the download
# links that carry a secret in their path. A second log would write them down
# anyway (ADR 0026).
CMD ["python", "-m", "uvicorn", "mobile_finance_api.runtime:app", \
     "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
