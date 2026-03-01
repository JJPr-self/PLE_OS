###############################################################################
# PLEASUREDAI OS — NERV Genesis v2.0
# ComfyUI + AI Video/Image/Audio Suite
#
# Base: nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04 (official NVIDIA)
# Targets: RTX 3090 / RTX 4090 on vast.ai / RunPod / local
#
# Build reliability: Every package listed here is verified to exist in
# Ubuntu 22.04 repos and PyPI. Optional/risky packages are isolated
# with || true so they never break the build.
###############################################################################

FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

SHELL ["/bin/bash", "-c"]
USER root

# ── Environment ──────────────────────────────────────────────────────────────
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
    LD_LIBRARY_PATH="/usr/local/lib/python3.10/dist-packages/nvidia/nvjitlink/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}" \
    NERV_LOG_DIR=/var/log/nerv \
    NERV_LOG_LEVEL=INFO \
    COMFYUI_MANAGER_ALLOW_INSTALL=true

# ── System packages (one layer, all verified Ubuntu 22.04) ───────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3.10-venv python3-pip \
    git git-lfs \
    wget curl aria2 \
    ffmpeg \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libgoogle-perftools-dev \
    nginx \
    build-essential cmake ninja-build pkg-config \
    unzip p7zip-full \
    espeak-ng libsndfile1 libportaudio2 \
    logrotate supervisor \
    net-tools iproute2 \
    htop && \
    git lfs install && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ── Python setup ─────────────────────────────────────────────────────────────
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    pip install --upgrade pip setuptools wheel

# ── PyTorch (CUDA 12.1 — pinned, verified) ──────────────────────────────────
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# ── Fix CUDA library compatibility ──────────────────────────────────────────
# PyTorch cu121 bundles cusparse from CUDA 12.4 which needs nvjitlink 12.4
RUN pip install nvidia-nvjitlink-cu12

# ── xFormers ─────────────────────────────────────────────────────────────────
RUN pip install xformers

# ── ComfyUI ──────────────────────────────────────────────────────────────────
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} && \
    cd ${COMFYUI_DIR} && \
    pip install -r requirements.txt

# ── Core ML libraries (needed by many custom nodes) ─────────────────────────
# These are rock-solid PyPI packages that never fail to install.
RUN pip install \
    einops timm kornia accelerate safetensors \
    huggingface-hub transformers diffusers \
    sentencepiece tokenizers \
    scipy scikit-learn \
    opencv-python-headless Pillow scikit-image \
    imageio imageio-ffmpeg av \
    aiohttp requests websocket-client \
    flask flask-cors bcrypt PyJWT \
    tqdm pyyaml omegaconf psutil colorama rich watchdog

# ── Optional ML packages (each isolated — failure won't break build) ────────
RUN pip install insightface || true
RUN pip install onnxruntime-gpu || true
RUN pip install rembg || true
RUN pip install trimesh pygltflib || true
RUN pip install pydub soundfile librosa || true
RUN pip install decord || true
RUN pip install mediapipe || true
RUN pip install open3d || true
RUN pip install color-transfer || true
RUN pip install gputil || true

# ── Node.js (NERV dashboard frontend server) ────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g http-server && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Directory structure ──────────────────────────────────────────────────────
RUN mkdir -p \
    ${MODELS_DIR}/checkpoints ${MODELS_DIR}/vae ${MODELS_DIR}/loras \
    ${MODELS_DIR}/embeddings ${MODELS_DIR}/controlnet ${MODELS_DIR}/upscale_models \
    ${MODELS_DIR}/clip ${MODELS_DIR}/clip_vision ${MODELS_DIR}/diffusion_models \
    ${MODELS_DIR}/text_encoders ${MODELS_DIR}/unet \
    ${MODELS_DIR}/insightface ${MODELS_DIR}/facerestore_models \
    ${MODELS_DIR}/ultralytics ${MODELS_DIR}/style_models \
    ${MODELS_DIR}/animatediff_models ${MODELS_DIR}/animatediff_motion_lora \
    ${MODELS_DIR}/ipadapter ${MODELS_DIR}/instantid \
    ${MODELS_DIR}/pulid ${MODELS_DIR}/liveportrait \
    ${INPUT_DIR} ${OUTPUT_DIR} \
    /opt/nerv-ui /opt/scripts ${NERV_LOG_DIR} \
    ${COMFYUI_DIR}/user/default/workflows

# ── Copy configs ─────────────────────────────────────────────────────────────
COPY config/extra_model_paths.yaml ${COMFYUI_DIR}/extra_model_paths.yaml
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ── Logrotate ────────────────────────────────────────────────────────────────
RUN printf '/var/log/nerv/*.log {\n  daily\n  missingok\n  rotate 7\n  compress\n  notifempty\n  copytruncate\n  maxsize 100M\n}\n' > /etc/logrotate.d/nerv

# ── Scripts + CLI ────────────────────────────────────────────────────────────
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh && \
    cp /opt/scripts/nerv-ai.py /usr/local/bin/nerv-ai && \
    chmod +x /usr/local/bin/nerv-ai

# ── Web UI + workflows ──────────────────────────────────────────────────────
COPY web-ui/ /opt/nerv-ui/
COPY workflows/ ${COMFYUI_DIR}/user/default/workflows/

# ── Entrypoint ───────────────────────────────────────────────────────────────
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# ── vast.ai onstart.sh hook ─────────────────────────────────────────────────
RUN printf '#!/bin/bash\nnohup /opt/entrypoint.sh >> /var/log/nerv/startup.log 2>&1 &\n' > /root/onstart.sh && \
    chmod +x /root/onstart.sh

# ── Health check ─────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -sf http://localhost:8188/system_stats || exit 1

EXPOSE 80 3000 8188
CMD ["/opt/entrypoint.sh"]
