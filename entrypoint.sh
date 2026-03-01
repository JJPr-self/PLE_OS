#!/bin/bash
###############################################################################
# PLEASUREDAI OS — Container Entrypoint (v2.1)
#
# PRIORITY: Get services UP fast, install extras in background.
# Order: GPU check → Auth → Start services → Install nodes (background)
###############################################################################

# ── Logging ──────────────────────────────────────────────────────────────────
NERV_LOG_DIR="${NERV_LOG_DIR:-/var/log/nerv}"
STARTUP_LOG="${NERV_LOG_DIR}/startup.log"
ERROR_LOG="${NERV_LOG_DIR}/errors.log"
mkdir -p "$NERV_LOG_DIR"

nerv_log() {
    local LEVEL="$1"; shift
    local MSG="$*"
    local TS="$(date '+%Y-%m-%d %H:%M:%S')"
    local FORMATTED="[${TS}] [NERV] [${LEVEL}] ${MSG}"
    echo "$FORMATTED"
    echo "$FORMATTED" >> "$STARTUP_LOG"
    if [ "$LEVEL" = "ERROR" ] || [ "$LEVEL" = "WARN" ]; then
        echo "$FORMATTED" >> "$ERROR_LOG"
    fi
}

# ── Prevent double-start ────────────────────────────────────────────────────
LOCKFILE="/tmp/nerv-entrypoint.lock"
if [ -f "$LOCKFILE" ]; then
    nerv_log "INFO" "Entrypoint already running (lockfile exists). Skipping."
    exit 0
fi
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# ── Banner ───────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  PLEASUREDAI OS — NERV GENESIS v2.1"
echo "  ComfyUI + AI Video/Image/Audio Suite"
echo "============================================================"
nerv_log "INFO" "=== NERV Genesis starting ==="

# ── Phase 1: GPU Check (non-fatal) ──────────────────────────────────────────
nerv_log "INFO" "Phase 1: GPU Verification"
if command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>&1) && \
        nerv_log "INFO" "GPU: ${GPU_INFO}" || \
        nerv_log "WARN" "nvidia-smi error: ${GPU_INFO}"
fi

# Quick PyTorch check (non-fatal — don't block startup)
nerv_log "INFO" "Phase 2: PyTorch Check"
python3 -c "
import torch
print(f'PyTorch {torch.__version__}, CUDA: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'GPU: {torch.cuda.get_device_name(0)}, VRAM: {torch.cuda.get_device_properties(0).total_mem/1024**3:.1f}GB')
" 2>&1 | while IFS= read -r line; do nerv_log "INFO" "  $line"; done
# Don't check exit code — continue regardless

# ── Phase 3: Auth Config ────────────────────────────────────────────────────
nerv_log "INFO" "Phase 3: Authentication"
AUTH_TOKEN="${AUTH_TOKEN:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))' 2>/dev/null || echo 'fallback_token')}"

cat > /opt/nerv-ui/auth_config.json <<EOF
{
    "username": "${AUTH_USERNAME:-nerv}",
    "password": "${AUTH_PASSWORD:-genesis}",
    "token": "${AUTH_TOKEN}",
    "session_timeout": 3600
}
EOF
chmod 600 /opt/nerv-ui/auth_config.json
nerv_log "INFO" "Auth config written"

# ── Phase 4: Model directories ──────────────────────────────────────────────
nerv_log "INFO" "Phase 4: Model Directories"
for dir in checkpoints vae loras embeddings controlnet upscale_models clip clip_vision \
    diffusion_models text_encoders unet insightface facerestore_models ultralytics \
    style_models animatediff_models animatediff_motion_lora ipadapter instantid pulid liveportrait; do
    mkdir -p "${MODELS_DIR:-/opt/comfyui/models}/${dir}"
done
mkdir -p "${INPUT_DIR:-/opt/comfyui/input}" "${OUTPUT_DIR:-/opt/comfyui/output}"

# ── Phase 5: VRAM detection for ComfyUI flags ───────────────────────────────
COMFY_ARGS="--listen 0.0.0.0 --port ${COMFYUI_PORT:-8188} --preview-method auto --fp16-vae"
VRAM_GB=$(python3 -c "
import torch
print(int(torch.cuda.get_device_properties(0).total_mem/1024**3)) if torch.cuda.is_available() else print(0)
" 2>/dev/null || echo "0")

if [ "$VRAM_GB" -ge 20 ] 2>/dev/null; then
    COMFY_ARGS="${COMFY_ARGS} --highvram"
    nerv_log "INFO" "GPU mode: HIGH VRAM (${VRAM_GB}GB)"
elif [ "$VRAM_GB" -ge 10 ] 2>/dev/null; then
    COMFY_ARGS="${COMFY_ARGS} --normalvram"
    nerv_log "INFO" "GPU mode: NORMAL VRAM (${VRAM_GB}GB)"
else
    COMFY_ARGS="${COMFY_ARGS} --lowvram"
    nerv_log "INFO" "GPU mode: LOW VRAM (${VRAM_GB}GB)"
fi

# ── Phase 6: START SERVICES (priority!) ─────────────────────────────────────
nerv_log "INFO" "Phase 6: Starting Services"

# Nginx
nerv_log "INFO" "→ Starting Nginx..."
nginx 2>> "$ERROR_LOG" && nerv_log "INFO" "  Nginx UP on port 80" || nerv_log "WARN" "  Nginx failed"

# NERV Web UI
nerv_log "INFO" "→ Starting NERV UI..."
cd /opt/nerv-ui
nohup python3 -m http.server ${NERV_UI_PORT:-3000} --bind 0.0.0.0 > "${NERV_LOG_DIR}/ui.log" 2>&1 &
nerv_log "INFO" "  NERV UI started on port ${NERV_UI_PORT:-3000}"

# ComfyUI
nerv_log "INFO" "→ Starting ComfyUI..."
nerv_log "INFO" "  Args: ${COMFY_ARGS}"
cd "${COMFYUI_DIR:-/opt/comfyui}"

# Detect environment for foreground vs background mode
if [ $$ -eq 1 ] || [ "${FOREGROUND:-1}" = "1" ]; then
    # ── Phase 7: Install nodes in BACKGROUND ────────────────────────────
    if [ -f /opt/scripts/install_nodes.sh ]; then
        nerv_log "INFO" "Phase 7: Installing custom nodes (background)..."
        nohup bash /opt/scripts/install_nodes.sh > "${NERV_LOG_DIR}/node_install.log" 2>&1 &
        nerv_log "INFO" "  Node installer running in background (PID: $!)"
    fi

    # Environment info
    if [ -n "$PUBLIC_IPADDR" ]; then
        nerv_log "INFO" "vast.ai: http://${PUBLIC_IPADDR}:${VAST_TCP_PORT_80:-80}"
    fi

    nerv_log "INFO" "═══════════════════════════════════════════════════"
    nerv_log "INFO" "  NERV Genesis v2.1 — Services launched"
    nerv_log "INFO" "  Use 'nerv-ai' CLI for management"
    nerv_log "INFO" "═══════════════════════════════════════════════════"

    # Foreground — exec replaces this process with ComfyUI
    exec python3 main.py ${COMFY_ARGS} 2>&1
else
    # Background mode (vast.ai onstart.sh)
    nohup python3 main.py ${COMFY_ARGS} > "${NERV_LOG_DIR}/comfyui.log" 2>&1 &
    COMFY_PID=$!
    nerv_log "INFO" "  ComfyUI started (PID: ${COMFY_PID})"

    # Install nodes in background
    if [ -f /opt/scripts/install_nodes.sh ]; then
        nohup bash /opt/scripts/install_nodes.sh > "${NERV_LOG_DIR}/node_install.log" 2>&1 &
    fi

    # Wait for ComfyUI API
    nerv_log "INFO" "  Waiting for ComfyUI API..."
    for i in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:${COMFYUI_PORT:-8188}/system_stats" > /dev/null 2>&1; then
            nerv_log "INFO" "  ComfyUI ready after ${i}s"
            break
        fi
        sleep 2
    done

    nerv_log "INFO" "═══════════════════════════════════════════════════"
    nerv_log "INFO" "  NERV Genesis v2.1 — All systems go"
    nerv_log "INFO" "═══════════════════════════════════════════════════"

    # Watchdog — restart ComfyUI if it crashes
    while true; do
        if ! kill -0 $COMFY_PID 2>/dev/null; then
            nerv_log "ERROR" "ComfyUI crashed! Restarting in 5s..."
            sleep 5
            cd "${COMFYUI_DIR:-/opt/comfyui}"
            nohup python3 main.py ${COMFY_ARGS} >> "${NERV_LOG_DIR}/comfyui.log" 2>&1 &
            COMFY_PID=$!
            nerv_log "INFO" "ComfyUI restarted (PID: ${COMFY_PID})"
        fi
        sleep 30
    done
fi
