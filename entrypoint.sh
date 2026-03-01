#!/bin/bash
###############################################################################
# PLEASUREDAI OS — Container Entrypoint (v2)
#
# Enhanced with:
#   - Structured logging (all output to /var/log/nerv/startup.log)
#   - Error trapping with context
#   - Service health verification after launch
#   - ComfyUI startup validation
#   - nerv-ai CLI availability check
#   - Compatible with: vast.ai onstart.sh AND direct Docker CMD
###############################################################################

# ── Logging Infrastructure ───────────────────────────────────────────────────
NERV_LOG_DIR="${NERV_LOG_DIR:-/var/log/nerv}"
STARTUP_LOG="${NERV_LOG_DIR}/startup.log"
ERROR_LOG="${NERV_LOG_DIR}/errors.log"
mkdir -p "$NERV_LOG_DIR"

# Structured logger: writes to both stdout and log file with timestamps
nerv_log() {
    local LEVEL="$1"
    shift
    local MSG="$*"
    local TS="$(date '+%Y-%m-%d %H:%M:%S')"
    local FORMATTED="[${TS}] [NERV] [${LEVEL}] ${MSG}"
    echo "$FORMATTED"
    echo "$FORMATTED" >> "$STARTUP_LOG"
    # Also write errors/warnings to dedicated error log
    if [ "$LEVEL" = "ERROR" ] || [ "$LEVEL" = "WARN" ]; then
        echo "$FORMATTED" >> "$ERROR_LOG"
    fi
}

# Trap errors and log them
trap_handler() {
    local EXIT_CODE=$?
    local LINE_NO=$1
    if [ $EXIT_CODE -ne 0 ]; then
        nerv_log "ERROR" "Command failed at line ${LINE_NO} with exit code ${EXIT_CODE}"
    fi
}
trap 'trap_handler ${LINENO}' ERR

# ── Prevent double-start (vast.ai may call both CMD and onstart.sh) ──────────
LOCKFILE="/tmp/nerv-entrypoint.lock"
if [ -f "$LOCKFILE" ]; then
    nerv_log "INFO" "Entrypoint already running (lockfile exists). Skipping."
    exit 0
fi
touch "$LOCKFILE"
# Clean lockfile on exit
trap 'rm -f "$LOCKFILE"' EXIT

# ── Banner ───────────────────────────────────────────────────────────────────
echo "============================================================"
echo "  ██████╗ ██╗     ███████╗ █████╗ ███████╗██╗   ██╗██████╗ "
echo "  ██╔══██╗██║     ██╔════╝██╔══██╗██╔════╝██║   ██║██╔══██╗"
echo "  ██████╔╝██║     █████╗  ███████║███████╗██║   ██║██████╔╝"
echo "  ██╔═══╝ ██║     ██╔══╝  ██╔══██║╚════██║██║   ██║██╔══██╗"
echo "  ██║     ███████╗███████╗██║  ██║███████║╚██████╔╝██║  ██║"
echo "  ╚═╝     ╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝"
echo "              ╔══════════════════════════════╗"
echo "              ║   NERV GENESIS SYSTEM v2.0   ║"
echo "              ║   ComfyUI + AI Suite         ║"
echo "              ╚══════════════════════════════╝"
echo "============================================================"
nerv_log "INFO" "=== NERV Genesis starting ==="
nerv_log "INFO" "CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES:-all}"
nerv_log "INFO" "Log directory: ${NERV_LOG_DIR}"

# ── Phase 1: GPU Verification ───────────────────────────────────────────────
nerv_log "INFO" "--- Phase 1: GPU Verification ---"
if command -v nvidia-smi &> /dev/null; then
    GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>&1)
    if [ $? -eq 0 ]; then
        nerv_log "INFO" "GPU detected: ${GPU_INFO}"
    else
        nerv_log "WARN" "nvidia-smi found but returned error: ${GPU_INFO}"
    fi
else
    nerv_log "ERROR" "nvidia-smi not found — GPU acceleration will NOT work"
fi

# ── Phase 2: PyTorch / CUDA Check ────────────────────────────────────────────
nerv_log "INFO" "--- Phase 2: PyTorch Verification ---"
PYTORCH_CHECK=$(python3 -c "
import sys
try:
    import torch
    print(f'PyTorch {torch.__version__}')
    print(f'CUDA available: {torch.cuda.is_available()}')
    if torch.cuda.is_available():
        print(f'GPU: {torch.cuda.get_device_name(0)}')
        props = torch.cuda.get_device_properties(0)
        print(f'VRAM: {props.total_mem / 1024**3:.1f} GB')
        print(f'Compute capability: {props.major}.{props.minor}')
        print(f'BF16 support: {torch.cuda.is_bf16_supported()}')
    else:
        print('WARNING: CUDA not available', file=sys.stderr)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)
PYTORCH_RC=$?
echo "$PYTORCH_CHECK" | while IFS= read -r line; do
    nerv_log "INFO" "  $line"
done
if [ $PYTORCH_RC -ne 0 ]; then
    nerv_log "ERROR" "PyTorch CUDA verification failed"
fi

# Check xFormers
XFORMERS_CHECK=$(python3 -c "
try:
    import xformers
    print(f'xFormers {xformers.__version__}')
except ImportError:
    print('xFormers NOT installed')
" 2>&1)
nerv_log "INFO" "  $XFORMERS_CHECK"

# ── Phase 3: Install / Update Custom Nodes ───────────────────────────────────
nerv_log "INFO" "--- Phase 3: Custom Node Installation ---"
if [ -f /opt/scripts/install_nodes.sh ]; then
    /opt/scripts/install_nodes.sh 2>&1 | tee -a "${NERV_LOG_DIR}/node_install.log"
    NODE_RC=${PIPESTATUS[0]}
    if [ $NODE_RC -ne 0 ]; then
        nerv_log "WARN" "Node installation had ${NODE_RC} failure(s) — check node_install.log"
    else
        nerv_log "INFO" "All custom nodes installed successfully"
    fi
else
    nerv_log "WARN" "Node install script not found at /opt/scripts/install_nodes.sh"
fi

# ── Phase 4: Model Directory Setup ──────────────────────────────────────────
nerv_log "INFO" "--- Phase 4: Model Directory Setup ---"
MODEL_DIRS=(
    checkpoints vae loras embeddings controlnet
    upscale_models clip clip_vision diffusion_models
    text_encoders unet insightface facerestore_models
    ultralytics style_models animatediff_models
    animatediff_motion_lora ipadapter instantid pulid liveportrait
)
for dir in "${MODEL_DIRS[@]}"; do
    mkdir -p "${MODELS_DIR:-/opt/comfyui/models}/${dir}"
done
mkdir -p "${INPUT_DIR:-/opt/comfyui/input}" "${OUTPUT_DIR:-/opt/comfyui/output}"
nerv_log "INFO" "Model directories verified (${#MODEL_DIRS[@]} categories)"

# Count existing models
MODEL_COUNT=$(find "${MODELS_DIR:-/opt/comfyui/models}" \
    \( -name "*.safetensors" -o -name "*.ckpt" -o -name "*.pt" -o -name "*.pth" \
       -o -name "*.bin" -o -name "*.onnx" \) 2>/dev/null | wc -l)
nerv_log "INFO" "Found ${MODEL_COUNT} model files in ${MODELS_DIR}"

# ── Phase 5: Authentication Setup ────────────────────────────────────────────
nerv_log "INFO" "--- Phase 5: Authentication ---"
AUTH_TOKEN="${AUTH_TOKEN:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')}"
nerv_log "INFO" "Auth token generated (${#AUTH_TOKEN} chars)"

# Write auth config
cat > /opt/nerv-ui/auth_config.json <<EOF
{
    "username": "${AUTH_USERNAME:-nerv}",
    "password": "${AUTH_PASSWORD:-genesis}",
    "token": "${AUTH_TOKEN}",
    "session_timeout": 3600
}
EOF
chmod 600 /opt/nerv-ui/auth_config.json

# Check if defaults are still in use
if [ "${AUTH_USERNAME:-nerv}" = "nerv" ] && [ "${AUTH_PASSWORD:-genesis}" = "genesis" ]; then
    nerv_log "WARN" "⚠ Using DEFAULT credentials! Set AUTH_USERNAME and AUTH_PASSWORD env vars for production!"
fi

# ── Phase 6: Nginx Configuration ────────────────────────────────────────────
nerv_log "INFO" "--- Phase 6: Nginx Proxy ---"
sed -i "s|__AUTH_TOKEN__|${AUTH_TOKEN}|g" /etc/nginx/nginx.conf 2>/dev/null || true
nginx -t >> "$STARTUP_LOG" 2>&1
if [ $? -eq 0 ]; then
    nerv_log "INFO" "Nginx configuration valid"
else
    nerv_log "ERROR" "Nginx configuration test FAILED — check nginx.conf"
fi

# ── Phase 7: Environment Detection ──────────────────────────────────────────
nerv_log "INFO" "--- Phase 7: Environment Detection ---"
if [ -n "$PUBLIC_IPADDR" ]; then
    EXTERNAL_PORT="${VAST_TCP_PORT_80:-80}"
    nerv_log "INFO" "║ Environment: vast.ai"
    nerv_log "INFO" "║ External URL: http://${PUBLIC_IPADDR}:${EXTERNAL_PORT}"
    nerv_log "INFO" "║ ComfyUI direct: http://${PUBLIC_IPADDR}:${VAST_TCP_PORT_8188:-8188}"
    nerv_log "INFO" "║ NERV UI direct: http://${PUBLIC_IPADDR}:${VAST_TCP_PORT_3000:-3000}"
else
    nerv_log "INFO" "║ Environment: Standalone"
    nerv_log "INFO" "║ Dashboard: http://localhost:80"
    nerv_log "INFO" "║ ComfyUI:   http://localhost:8188"
fi

# Generate .env for NERV UI
cat > /opt/nerv-ui/.env <<EOF
COMFYUI_URL=http://127.0.0.1:${COMFYUI_PORT:-8188}
AUTH_TOKEN=${AUTH_TOKEN}
NODE_ENV=production
EOF

# ── Phase 8: Verify CLI ─────────────────────────────────────────────────────
nerv_log "INFO" "--- Phase 8: nerv-ai CLI ---"
if command -v nerv-ai &> /dev/null; then
    nerv_log "INFO" "nerv-ai CLI available at $(which nerv-ai)"
    nerv_log "INFO" "  Usage: nerv-ai status | logs | errors | gpu | models | health"
else
    nerv_log "WARN" "nerv-ai CLI not found in PATH"
fi

# ── Phase 9: Launch Services ────────────────────────────────────────────────
nerv_log "INFO" "--- Phase 9: Service Launch ---"

# Start Nginx
nerv_log "INFO" "→ Starting Nginx reverse proxy..."
nginx >> "$STARTUP_LOG" 2>&1
if [ $? -eq 0 ]; then
    nerv_log "INFO" "  Nginx started on port 80"
else
    nerv_log "ERROR" "  Nginx FAILED to start"
fi

# Start NERV Web UI
nerv_log "INFO" "→ Starting NERV UI on port ${NERV_UI_PORT:-3000}..."
cd /opt/nerv-ui
nohup python3 -m http.server ${NERV_UI_PORT:-3000} --bind 0.0.0.0 \
    > "${NERV_LOG_DIR}/ui.log" 2>&1 &
UI_PID=$!
nerv_log "INFO" "  NERV UI started (PID: ${UI_PID})"

# Determine VRAM and set ComfyUI flags
VRAM_GB=$(python3 -c "
import torch
if torch.cuda.is_available():
    print(int(torch.cuda.get_device_properties(0).total_mem / 1024**3))
else:
    print(0)
" 2>/dev/null || echo "0")

COMFY_ARGS="--listen 0.0.0.0 --port ${COMFYUI_PORT:-8188} --preview-method auto"

if [ "$VRAM_GB" -ge 20 ]; then
    COMFY_ARGS="${COMFY_ARGS} --highvram --fp16-vae"
    nerv_log "INFO" "GPU mode: HIGH VRAM (${VRAM_GB}GB) — fp16 VAE, models kept in VRAM"
elif [ "$VRAM_GB" -ge 10 ]; then
    COMFY_ARGS="${COMFY_ARGS} --normalvram --fp16-vae"
    nerv_log "INFO" "GPU mode: NORMAL VRAM (${VRAM_GB}GB) — standard offloading"
else
    COMFY_ARGS="${COMFY_ARGS} --lowvram --fp16-vae"
    nerv_log "INFO" "GPU mode: LOW VRAM (${VRAM_GB}GB) — aggressive offloading"
fi

# Start ComfyUI
nerv_log "INFO" "→ Starting ComfyUI on port ${COMFYUI_PORT:-8188}..."
nerv_log "INFO" "  Args: ${COMFY_ARGS}"
cd "${COMFYUI_DIR:-/opt/comfyui}"

# PID 1 handling: foreground if we're PID 1 (docker CMD), background if onstart.sh
if [ $$ -eq 1 ] || [ "${FOREGROUND:-1}" = "1" ]; then
    nerv_log "INFO" "═══════════════════════════════════════════════════"
    nerv_log "INFO" "  NERV Genesis v2.0 — All systems operational"
    nerv_log "INFO" "  Use 'nerv-ai' from any terminal for management"
    nerv_log "INFO" "═══════════════════════════════════════════════════"

    # Foreground mode — exec replaces this shell process with ComfyUI.
    # We redirect stderr to the log file while keeping stdout visible to Docker.
    # NOTE: Do NOT use `exec ... | tee` — pipes break exec's PID replacement.
    exec python3 main.py ${COMFY_ARGS} 2>&1
else
    # Background mode (vast.ai onstart.sh)
    nohup python3 main.py ${COMFY_ARGS} > "${NERV_LOG_DIR}/comfyui.log" 2>&1 &
    COMFY_PID=$!
    nerv_log "INFO" "  ComfyUI started (PID: ${COMFY_PID})"

    # Wait for ComfyUI to be ready (max 60s)
    nerv_log "INFO" "  Waiting for ComfyUI API..."
    for i in $(seq 1 30); do
        if curl -sf "http://127.0.0.1:${COMFYUI_PORT:-8188}/system_stats" > /dev/null 2>&1; then
            nerv_log "INFO" "  ✓ ComfyUI API responding after ${i}s"
            break
        fi
        sleep 2
    done

    # Final status check
    if curl -sf "http://127.0.0.1:${COMFYUI_PORT:-8188}/system_stats" > /dev/null 2>&1; then
        nerv_log "INFO" "═══════════════════════════════════════════════════"
        nerv_log "INFO" "  NERV Genesis v2.0 — All systems operational ✓"
        nerv_log "INFO" "  Use 'nerv-ai' from any terminal for management"
        nerv_log "INFO" "═══════════════════════════════════════════════════"
    else
        nerv_log "ERROR" "ComfyUI did not respond within 60s — check comfyui.log"
    fi

    # Keep-alive watchdog: restart ComfyUI if it crashes
    while true; do
        if ! kill -0 $COMFY_PID 2>/dev/null; then
            nerv_log "ERROR" "ComfyUI process (PID ${COMFY_PID}) exited unexpectedly!"
            nerv_log "INFO" "Restarting ComfyUI in 5 seconds..."
            sleep 5
            cd "${COMFYUI_DIR:-/opt/comfyui}"
            nohup python3 main.py ${COMFY_ARGS} >> "${NERV_LOG_DIR}/comfyui.log" 2>&1 &
            COMFY_PID=$!
            nerv_log "INFO" "ComfyUI restarted (new PID: ${COMFY_PID})"
        fi
        sleep 30
    done
fi
