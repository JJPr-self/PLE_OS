###############################################################################
# PLEASUREDAI OS — ComfyUI + AI Video/Image/Audio Suite (v2)
# Base: NVIDIA CUDA 12.1.1 + cuDNN 8 on Ubuntu 22.04
# Targets: RTX 3090 / RTX 4090 on vast.ai, RunPod, Lambda, or local
#
# Key improvements (v2):
#   - nerv-ai CLI installed globally (/usr/local/bin/nerv-ai)
#   - Structured logging to /var/log/nerv/
#   - ComfyUI Manager pre-configured for CivitAI model imports
#   - Additional pip packages for 3D, audio, advanced vision
#   - logrotate for log management
###############################################################################

FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

# Force standard bash shell (prevents inherited SHELL wrapper issues)
SHELL ["/bin/bash", "-c"]

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
    PATH="/usr/local/cuda/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}" \
    NERV_LOG_DIR=/var/log/nerv \
    NERV_LOG_LEVEL=INFO \
    COMFYUI_MANAGER_ALLOW_INSTALL=true

# ── System Dependencies ─────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-venv python3.10-dev python3-pip \
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

# ── Python Symlinks ─────────────────────────────────────────────────────────
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1

# ── Pip Upgrade ──────────────────────────────────────────────────────────────
RUN pip install --upgrade pip setuptools wheel

# ── PyTorch + CUDA 12.1 ─────────────────────────────────────────────────────
RUN pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu121

# ── xFormers (memory-efficient attention) ────────────────────────────────────
RUN pip install xformers

# ── ComfyUI Installation ────────────────────────────────────────────────────
RUN git clone https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} && \
    cd ${COMFYUI_DIR} && \
    pip install -r requirements.txt

# ── AI / ML Python Dependencies ─────────────────────────────────────────────
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
    rembg

# Video processing
RUN pip install \
    imageio imageio-ffmpeg \
    av \
    decord

# Audio / TTS (pyaudio may fail without dev headers — non-fatal)
RUN pip install \
    TTS \
    pydub \
    soundfile \
    librosa && \
    pip install pyaudio 2>/dev/null || true

# Face detection / swap (mediapipe may not build everywhere — non-fatal)
RUN pip install \
    insightface \
    onnxruntime-gpu && \
    pip install mediapipe 2>/dev/null || true

# 3D / depth estimation (open3d is large and may fail — non-fatal)
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
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g http-server && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

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
RUN printf '/var/log/nerv/*.log {\n    daily\n    missingok\n    rotate 7\n    compress\n    notifempty\n    copytruncate\n    maxsize 100M\n}\n' > /etc/logrotate.d/nerv

# ── Copy Scripts ─────────────────────────────────────────────────────────────
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# ── Install nerv-ai CLI globally ─────────────────────────────────────────────
RUN cp /opt/scripts/nerv-ai.py /usr/local/bin/nerv-ai && \
    chmod +x /usr/local/bin/nerv-ai

# ── Copy NERV Web UI ────────────────────────────────────────────────────────
COPY web-ui/ /opt/nerv-ui/
COPY workflows/ ${COMFYUI_DIR}/user/default/workflows/

# ── Copy Entrypoint ─────────────────────────────────────────────────────────
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# ── vast.ai Autostart Hook ──────────────────────────────────────────────────
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
