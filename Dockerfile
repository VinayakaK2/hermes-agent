# Production Dockerfile for deploying Hermes Agent on Render
FROM nousresearch/hermes-agent:latest

USER root

# Install Python packages for cloud persistence (huggingface_hub) and sandbox (e2b)
RUN pip install --no-cache-dir --break-system-packages huggingface_hub e2b-code-interpreter || \
    pip install --no-cache-dir huggingface_hub e2b-code-interpreter

ENV PORT=8000
ENV API_SERVER_HOST=0.0.0.0
ENV API_SERVER_PORT=8000
ENV API_SERVER_ENABLED=true
ENV HERMES_HOME=/opt/data
ENV PYTHONUNBUFFERED=1

WORKDIR /opt/hermes

# Copy cloud runner scripts and default configuration
COPY cloud/hf_sync.py /opt/hermes/cloud/hf_sync.py
COPY cloud/entrypoint.sh /opt/hermes/cloud/entrypoint.sh
COPY cloud/default_config.yaml /opt/hermes/cloud/default_config.yaml

RUN chmod +x /opt/hermes/cloud/entrypoint.sh /opt/hermes/cloud/hf_sync.py \
    && mkdir -p /opt/data \
    && chown -R 10000:10000 /opt/data /opt/hermes/cloud

USER hermes

EXPOSE 8000

ENTRYPOINT ["/opt/hermes/cloud/entrypoint.sh"]
