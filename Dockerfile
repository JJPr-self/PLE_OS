###############################################################################
# PLEASUREDAI OS — ComfyUI + AI Video/Image/Audio Suite (v2)
# Base: vast.ai CUDA 12.1.1 (Ubuntu 22.04)
# Targets: RTX 3090 / RTX 4090 on vast.ai
#
# Build time target: <10 minutes
# Key improvements (v2):
#   - nerv-ai CLI installed globally (/usr/local/bin/nerv-ai)
#   - Structured logging to /var/log/nerv/
#   - ComfyUI Manager pre-configured for CivitAI model imports
#   - Additional pip packages for 3D, audio, advanced vision
#   - logrotate for log management
###############################################################################

FROM vastai/base-image:cuda-12.1.1-auto

USER root

# ── Environment Variables ────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    COMFYUI_PORT=8188 \
    COMFYUI_DIR=/opt/comfyui \
    MODELS_DIR=/opt/comfyui/models \
    CUSTOM_NODES_DIR=/opt/comfyui/custom_nodes \
    OUTPUT_DIR=/opt/comfyui/output \
    INPUT_DIR=/opt/comfyui/input \
    NERV_UI_PORT=3000 \
    AUTH_TOKEN="" \
    AUTH_USERNAME="nerv" \
    AUTH_PASSWORD="genesis" \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,video \
    TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9+PTX" \
    CUDA_HOME=/usr/local/cuda \
    # Logging
    NERV_LOG_DIR=/var/log/nerv \
    NERV_LOG_LEVEL=INFO \
    # ComfyUI Manager settings
    COMFYUI_MANAGER_ALLOW_INSTALL=true

# ── System Dependencies ─────────────────────────────────────────────────────
# Split into two stages: essential (must succeed) and optional (can fail).
# The vast.ai base image already has Python, CUDA, and some tools installed.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git git-lfs \
    wget curl aria2 \
    ffmpeg \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libgoogle-perftools-dev \
    nginx \
    build-essential cmake ninja-build pkg-config \
    unzip p7zip-full \
    espeak-ng libsndfile1 libportaudio2 \
    logrotate \
    supervisor \
    net-tools iproute2 dnsutils \
    htop iotop \
    && git lfs install \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install optional packages that may not exist in all base images (non-fatal)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-dev python3-venv \
    libopencv-dev \
    2>/dev/null; \
    apt-get clean && rm -rf /var/lib/apt/lists/* || true

# ── Python Symlinks ─────────────────────────────────────────────────────────
# vast.ai base image may already have python3 — only create if missing
RUN which python3 || update-alternatives --install /usr/bin/python3 python3 $(which python3.10 || which python3.11 || which python3) 1; \
    which python || ln -sf $(which python3) /usr/bin/python || true

# ── Pip Upgrade ──────────────────────────────────────────────────────────────
RUN pip install --upgrade pip setuptools wheel

# ── PyTorch + CUDA 12.1 ─────────────────────────────────────────────────────
# Stable release pinned to cu121 for CUDA 12.1.1 compatibility.
RUN pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu121

# ── xFormers (memory-efficient attention) ────────────────────────────────────
# Reduces VRAM usage ~40% on RTX 30/40 series via FlashAttention
RUN pip install xformers

# ── ComfyUI Installation ────────────────────────────────────────────────────
# Official repo, depth=1 for speed. We install from requirements.txt which
# pins compatible versions of all ComfyUI core dependencies.
RUN git clone https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} \
    && cd ${COMFYUI_DIR} \
    && pip install -r requirements.txt

# ── AI / ML Python Dependencies ─────────────────────────────────────────────
# Split into logical groups. Each group is one layer for cache efficiency.

# Core ML & optimization
RUN pip install \
    einops timm kornia \
    accelerate \
    safetensors \
    huggingface-hub \
    transformers \
    diffusers \
    sentencepiece \
    tokenizers \
    scipy \
    scikit-learn

# Image processing
RUN pip install \
    opencv-python-headless \
    Pillow \
    scikit-image \
    color-transfer \
    rembg[gpu]

# Video processing
RUN pip install \
    imageio imageio-ffmpeg \
    av \
    decord

# Audio / TTS
RUN pip install \
    TTS \
    pydub \
    soundfile \
    librosa \
    pyaudio 2>/dev/null || true

# Face detection / swap
RUN pip install \
    insightface \
    onnxruntime-gpu \
    mediapipe 2>/dev/null || true

# 3D / depth estimation
RUN pip install trimesh pygltflib && \
    pip install open3d 2>/dev/null || true

# Web API / networking
RUN pip install \
    aiohttp \
    requests \
    websocket-client \
    flask flask-cors \
    bcrypt PyJWT

# Utilities
RUN pip install \
    tqdm pyyaml omegaconf \
    psutil gputil \
    colorama \
    rich \
    watchdog

# ── Node.js for NERV Frontend ───────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g http-server \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Create Directory Structure ───────────────────────────────────────────────
RUN mkdir -p \
    ${MODELS_DIR}/checkpoints \
    ${MODELS_DIR}/vae \
    ${MODELS_DIR}/loras \
    ${MODELS_DIR}/embeddings \
    ${MODELS_DIR}/controlnet \
    ${MODELS_DIR}/upscale_models \
    ${MODELS_DIR}/clip \
    ${MODELS_DIR}/clip_vision \
    ${MODELS_DIR}/diffusion_models \
    ${MODELS_DIR}/text_encoders \
    ${MODELS_DIR}/unet \
    ${MODELS_DIR}/insightface \
    ${MODELS_DIR}/facerestore_models \
    ${MODELS_DIR}/ultralytics \
    ${MODELS_DIR}/style_models \
    ${MODELS_DIR}/animatediff_models \
    ${MODELS_DIR}/animatediff_motion_lora \
    ${MODELS_DIR}/ipadapter \
    ${MODELS_DIR}/instantid \
    ${MODELS_DIR}/pulid \
    ${MODELS_DIR}/liveportrait \
    ${INPUT_DIR} \
    ${OUTPUT_DIR} \
    /opt/nerv-ui \
    /opt/scripts \
    ${NERV_LOG_DIR} \
    ${COMFYUI_DIR}/user/default/workflows

# ── Copy Configuration Files ────────────────────────────────────────────────
COPY config/extra_model_paths.yaml ${COMFYUI_DIR}/extra_model_paths.yaml
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# ── Logrotate Config ────────────────────────────────────────────────────────
# Prevents log files from filling disk on long-running instances
RUN echo '/var/log/nerv/*.log {\n\
    daily\n\
    missingok\n\
    rotate 7\n\
    compress\n\
    notifempty\n\
    copytruncate\n\
    maxsize 100M\n\
    }' > /etc/logrotate.d/nerv

# ── Copy Scripts ─────────────────────────────────────────────────────────────
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# ── Install nerv-ai CLI globally ─────────────────────────────────────────────
# Makes `nerv-ai` command available from any directory in the container.
# The .py file already has #!/usr/bin/env python3 shebang.
RUN cp /opt/scripts/nerv-ai.py /usr/local/bin/nerv-ai \
    && chmod +x /usr/local/bin/nerv-ai

# ── Copy NERV Web UI ────────────────────────────────────────────────────────
COPY web-ui/ /opt/nerv-ui/
COPY workflows/ ${COMFYUI_DIR}/user/default/workflows/

# ── Copy Entrypoint ─────────────────────────────────────────────────────────
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# ── vast.ai Autostart Hook ──────────────────────────────────────────────────
# vast.ai overrides ENTRYPOINT. onstart.sh ensures our processes launch.
RUN printf '#!/bin/bash\nnohup /opt/entrypoint.sh >> /var/log/nerv/startup.log 2>&1 &\n' \
    > /root/onstart.sh \
    && chmod +x /root/onstart.sh

# ── Supervisor Configuration ────────────────────────────────────────────────
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ── Health Check ─────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -sf http://localhost:${COMFYUI_PORT}/system_stats || exit 1

# ── Expose Ports ─────────────────────────────────────────────────────────────
EXPOSE 80 3000 8188

# ── Default Command ──────────────────────────────────────────────────────────
CMD ["/opt/entrypoint.sh"]
