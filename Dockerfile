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
ENV HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
ENV HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=5002112A
ENV HERMES_DASHBOARD_BASIC_AUTH_SECRET=hermes-render-cloud-persistent-token-signing-secret-2026
ENV HERMES_HOME=/opt/data
ENV HERMES_WRITE_SAFE_ROOT=/opt/data
ENV HERMES_WEB_DIST=/opt/hermes/apps/desktop/dist-webapp
ENV HERMES_UI_SURFACE=webapp
ENV PYTHONUNBUFFERED=1
ENV MALLOC_ARENA_MAX=2
ENV PYTHONMALLOC=malloc
ENV HERMES_TUI_RPC_POOL_WORKERS=2
ENV WEB_CONCURRENCY=1
ENV PATH="/opt/hermes/bin:/opt/hermes/.venv/bin:/usr/local/bin:${PATH}"

WORKDIR /opt/hermes

# Copy cloud runner scripts and default configuration
COPY cloud/hf_sync.py /opt/hermes/cloud/hf_sync.py
COPY cloud/entrypoint.sh /opt/hermes/cloud/entrypoint.sh
COPY cloud/default_config.yaml /opt/hermes/cloud/default_config.yaml

# Copy updated hermes_cli web server modules for Desktop Webapp UI support
COPY hermes_cli/web_server.py /opt/hermes/hermes_cli/web_server.py
COPY hermes_cli/web_server_surface.py /opt/hermes/hermes_cli/web_server_surface.py
COPY hermes_cli/web_server_dashboard.py /opt/hermes/hermes_cli/web_server_dashboard.py

# Copy updated tui_gateway contract modules for Desktop Webapp compatibility
COPY tui_gateway/contracts/sessions.py /opt/hermes/tui_gateway/contracts/sessions.py
COPY tui_gateway/contracts/prompt_voice.py /opt/hermes/tui_gateway/contracts/prompt_voice.py
COPY tui_gateway/contracts/registry.py /opt/hermes/tui_gateway/contracts/registry.py
COPY tui_gateway/methods_prompt.py /opt/hermes/tui_gateway/methods_prompt.py
COPY tui_gateway/session_auto_continue.py /opt/hermes/tui_gateway/session_auto_continue.py

RUN chmod +x /opt/hermes/cloud/entrypoint.sh /opt/hermes/cloud/hf_sync.py \
    && mkdir -p /opt/data /tmp/hermes-runtime \
    && chown -R 10000:10000 /opt/data /opt/hermes/cloud /tmp/hermes-runtime /opt/hermes/hermes_cli /opt/hermes/tui_gateway \
    && chmod -R 777 /opt/data /tmp/hermes-runtime

USER hermes

EXPOSE 8000

ENTRYPOINT ["/opt/hermes/cloud/entrypoint.sh"]
