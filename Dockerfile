# Production Dockerfile for deploying Hermes Agent on Render
FROM nousresearch/hermes-agent:latest

USER root

# Install Python packages for cloud persistence (huggingface_hub) and sandbox (e2b)
RUN set -e; \
    UV_BIN="$(python3 -c 'from pm.install import installed_package; print(installed_package("uv").binary)' 2>/dev/null || true)"; \
    if [ -z "$UV_BIN" ] || [ ! -x "$UV_BIN" ]; then \
        curl -LsSf https://astral.sh/uv/install.sh | sh || true; \
        export PATH="/root/.cargo/bin:/root/.local/bin:${PATH}"; \
        UV_BIN="$(which uv || true)"; \
    fi; \
    if [ -n "$UV_BIN" ] && [ -x "$UV_BIN" ]; then \
        "$UV_BIN" pip install --python /opt/hermes/.venv huggingface_hub e2b-code-interpreter; \
    else \
        apt-get update && apt-get install -y --no-install-recommends python3-pip && \
        /opt/hermes/.venv/bin/python -m pip install --break-system-packages --no-cache-dir huggingface_hub e2b-code-interpreter && \
        rm -rf /var/lib/apt/lists/*; \
    fi; \
    chmod -R a+rX /opt/hermes/.venv

ENV PORT=8000
ENV HERMES_DASHBOARD=true
ENV HERMES_DASHBOARD_HOST=0.0.0.0
ENV HERMES_DASHBOARD_PORT=8000
ENV HERMES_HOME=/opt/data
ENV HERMES_WRITE_SAFE_ROOT=/opt/data
ENV PYTHONUNBUFFERED=1
ENV PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:/usr/local/bin:${PATH}"

WORKDIR /opt/hermes

# Copy cloud runner scripts and default configuration
COPY cloud/hf_sync.py /opt/hermes/cloud/hf_sync.py
COPY cloud/entrypoint.sh /opt/hermes/cloud/entrypoint.sh
COPY cloud/default_config.yaml /opt/hermes/cloud/default_config.yaml

RUN chmod +x /opt/hermes/cloud/entrypoint.sh /opt/hermes/cloud/hf_sync.py \
    && mkdir -p /opt/data /tmp/hermes-runtime \
    && chown -R 10000:10000 /opt/data /opt/hermes/cloud /tmp/hermes-runtime \
    && chmod -R 777 /opt/data /tmp/hermes-runtime

USER hermes

EXPOSE 8000

ENTRYPOINT ["/opt/hermes/cloud/entrypoint.sh"]
