###############################################################################
# PLEASUREDAI OS — NERV Genesis v3.0 (ULTRA-LEAN BUILD)
#
# MISSION: 
# 1. Build in < 15 mins (was > 1 hour)
# 2. NO dynamic downloads during build (except OS/Pip packages)
# 3. NO models in image (installed via setup.sh at runtime)
# 4. PREVENT version thrashing (standardized base dependencies)
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
    NERV_UI_PORT=3000

# ── 1. OS Essentials (Pinned & Consolidated) ────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3-pip \
    git git-lfs wget curl aria2 ffmpeg \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libgoogle-perftools-dev nginx logrotate supervisor \
    unzip p7zip-full build-essential cmake ninja-build \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── 2. Python Base ──────────────────────────────────────────────────────────
RUN pip install --upgrade pip setuptools wheel

# ── 3. High-Performance Core (The "Heavy" Layer) ────────────────────────────
# We install the big ones once to prevent the "uninstall/reinstall" loop.
RUN pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
RUN pip install nvidia-nvjitlink-cu12 xformers onnxruntime-gpu

# ── 4. ComfyUI & Standard ML Stack ──────────────────────────────────────────
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} \
    && cd ${COMFYUI_DIR} && pip install -r requirements.txt

# Consolidated pip install for ALL core dependencies to avoid layer bloat
RUN pip install \
    einops timm kornia accelerate safetensors \
    huggingface-hub transformers diffusers \
    sentencepiece tokenizers scipy scikit-learn \
    opencv-python-headless Pillow scikit-image \
    imageio imageio-ffmpeg av aiohttp requests \
    websocket-client gradio flask flask-cors \
    bcrypt PyJWT tqdm pyyaml omegaconf psutil \
    rich watchdog decord mediapipe pydub soundfile || true

# ── 5. Tools & Server ───────────────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs && npm install -g http-server \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── 6. Structure ────────────────────────────────────────────────────────────
RUN mkdir -p /opt/nerv-ui /opt/scripts /var/log/nerv \
    ${COMFYUI_DIR}/models ${COMFYUI_DIR}/custom_nodes ${COMFYUI_DIR}/user/default/workflows

# ── 7. Configs ──────────────────────────────────────────────────────────────
COPY config/extra_model_paths.yaml ${COMFYUI_DIR}/extra_model_paths.yaml
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ── 8. Scripts / UI (The "Fast" Layers) ─────────────────────────────────────
# We copy these LAST so that code changes don't invalidate the slow layers above.
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh && ln -s /opt/scripts/nerv-ai.py /usr/local/bin/nerv-ai || true

COPY web-ui/ /opt/nerv-ui/
COPY workflows/ ${COMFYUI_DIR}/user/default/workflows/

# ── 9. Critical Change: REMOVED install_nodes.sh from build ────────────────
# REASON: It takes 40+ mins and often fails/reinstalls. User will run setup.sh instead.

COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# onstart.sh for vast.ai
RUN printf '#!/bin/bash\nnohup /opt/entrypoint.sh >> /var/log/nerv/startup.log 2>&1 &\n' > /root/onstart.sh && chmod +x /root/onstart.sh

EXPOSE 80 3000 8188 7860
CMD ["/opt/entrypoint.sh"]
