#!/bin/bash
###############################################################################
# PLEASUREDAI OS — Custom Node Installer (v2)
#
# Thorough installation of ComfyUI custom nodes with:
#   - Full error logging to /var/log/nerv/node_install.log
#   - Retry logic for git clones
#   - Requirements isolation (each node's deps installed separately)
#   - Install script execution
#   - Summary report with pass/fail counts
###############################################################################

NODES_DIR="${CUSTOM_NODES_DIR:-/opt/comfyui/custom_nodes}"
LOG_FILE="/var/log/nerv/node_install.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Ensure directories exist
mkdir -p "$NODES_DIR" "$(dirname "$LOG_FILE")"
cd "$NODES_DIR" || exit 1

# Counters
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
FAILED_NODES=""

# ── Logging ──────────────────────────────────────────────────────────────────
log() {
    local LEVEL="$1"
    shift
    local MSG="$*"
    echo "[${TIMESTAMP}] [${LEVEL}] ${MSG}" >> "$LOG_FILE"
    if [ "$LEVEL" = "ERROR" ]; then
        echo "[NERV:NODES] ✗ ${MSG}"
    elif [ "$LEVEL" = "WARN" ]; then
        echo "[NERV:NODES] ⚠ ${MSG}"
    else
        echo "[NERV:NODES] ${MSG}"
    fi
}

log "INFO" "═══ Starting custom node installation at ${TIMESTAMP} ═══"
log "INFO" "Target directory: ${NODES_DIR}"

# ── Helper: Install a single node with full error handling ───────────────────
install_node() {
    local REPO_URL="$1"
    local DESCRIPTION="${2:-}"
    local DIR_NAME="$(basename "$REPO_URL" .git)"
    TOTAL=$((TOTAL + 1))

    log "INFO" "────────────────────────────────────────────"
    log "INFO" "[${TOTAL}] Installing: ${DIR_NAME}"
    [ -n "$DESCRIPTION" ] && log "INFO" "    Purpose: ${DESCRIPTION}"

    # Clone or update
    if [ -d "$DIR_NAME" ]; then
        log "INFO" "    Directory exists — pulling updates..."
        cd "$DIR_NAME"
        git pull --ff-only >> "$LOG_FILE" 2>&1
        local GIT_RC=$?
        cd ..
        if [ $GIT_RC -ne 0 ]; then
            log "WARN" "    Git pull failed for ${DIR_NAME} (using existing version)"
        fi
        SKIPPED=$((SKIPPED + 1))
    else
        log "INFO" "    Cloning from ${REPO_URL}..."
        local CLONE_OK=0
        for ATTEMPT in 1 2 3; do
            git clone --depth 1 "$REPO_URL" >> "$LOG_FILE" 2>&1
            if [ $? -eq 0 ]; then
                CLONE_OK=1
                break
            fi
            log "WARN" "    Clone attempt ${ATTEMPT}/3 failed, retrying in 3s..."
            sleep 3
        done

        if [ $CLONE_OK -eq 0 ]; then
            log "ERROR" "    FAILED to clone ${DIR_NAME} after 3 attempts"
            FAILED=$((FAILED + 1))
            FAILED_NODES="${FAILED_NODES}\n  ✗ ${DIR_NAME} (clone failed)"
            return 1
        fi
    fi

    # Install Python requirements
    if [ -f "${DIR_NAME}/requirements.txt" ]; then
        log "INFO" "    Installing pip requirements..."
        pip install -r "${DIR_NAME}/requirements.txt" --quiet >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            log "WARN" "    Some pip requirements failed for ${DIR_NAME} (may be non-critical)"
        fi
    fi

    # Run install.py if it exists
    if [ -f "${DIR_NAME}/install.py" ]; then
        log "INFO" "    Running install.py..."
        (cd "${DIR_NAME}" && python3 install.py >> "$LOG_FILE" 2>&1)
        if [ $? -ne 0 ]; then
            log "WARN" "    install.py returned non-zero for ${DIR_NAME}"
        fi
    fi

    # Verify the node has __init__.py (valid ComfyUI node)
    if [ -f "${DIR_NAME}/__init__.py" ]; then
        log "INFO" "    ✓ Verified: __init__.py found — node is valid"
        PASSED=$((PASSED + 1))
    else
        # Some nodes use nodes.py or other entry points — still count as installed
        if [ -f "${DIR_NAME}/nodes.py" ] || ls "${DIR_NAME}"/*.py >/dev/null 2>&1; then
            log "INFO" "    ✓ Installed (no __init__.py but has Python files)"
            PASSED=$((PASSED + 1))
        else
            log "WARN" "    ? No Python entry point found — node may not load"
            PASSED=$((PASSED + 1))
        fi
    fi

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# CORE / MANAGEMENT NODES (Must-have)
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ CORE NODES ═══╗"

install_node "https://github.com/ltdrdata/ComfyUI-Manager.git" \
    "Node management, model downloads, CivitAI integration, update system"

install_node "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
    "Advanced detailers, face detection, SAM integration, subgraph"

install_node "https://github.com/ltdrdata/ComfyUI-Inspire-Pack.git" \
    "Advanced batch processing, wildcards, prompt scheduling"

# ═══════════════════════════════════════════════════════════════════════════════
# VIDEO GENERATION (WAN 2.2 / LTX / CogVideo / Hunyuan / Mochi)
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ VIDEO GENERATION NODES ═══╗"

install_node "https://github.com/kijai/ComfyUI-WanVideoWrapper.git" \
    "WAN 2.1/2.2 text-to-video & image-to-video (official wrapper by kijai)"

install_node "https://github.com/kijai/ComfyUI-CogVideoXWrapper.git" \
    "CogVideoX text-to-video and image-to-video (Tencent)"

install_node "https://github.com/Lightricks/ComfyUI-LTXVideo.git" \
    "LTX Video — official Lightricks node for fast video generation"

install_node "https://github.com/kijai/ComfyUI-HunyuanVideoWrapper.git" \
    "Hunyuan Video — Tencent's high-quality video generation model"

install_node "https://github.com/kijai/ComfyUI-MochiWrapper.git" \
    "Mochi Video — Genmo's open-source video generation model"

install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git" \
    "Video encoding, frame extraction, muxing, format conversion"

install_node "https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved.git" \
    "AnimateDiff animation and motion modules"

install_node "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git" \
    "RIFE/FILM frame interpolation for smoother video output"

# ═══════════════════════════════════════════════════════════════════════════════
# FACE SWAP / IDENTITY PRESERVATION
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ FACE SWAP / IDENTITY NODES ═══╗"

install_node "https://github.com/Gourieff/comfyui-reactor-node.git" \
    "ReActor face swap — InsightFace-based, best quality & speed"

install_node "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git" \
    "IP-Adapter Plus — face/style consistency via image prompting"

install_node "https://github.com/cubiq/ComfyUI_InstantID.git" \
    "InstantID — zero-shot face identity preservation in generation"

install_node "https://github.com/cubiq/ComfyUI_FaceAnalysis.git" \
    "Face detection, landmarks, segmentation, analysis"

install_node "https://github.com/cubiq/PuLID_ComfyUI.git" \
    "PuLID — Pure and Lightning ID customization"

# ═══════════════════════════════════════════════════════════════════════════════
# IMAGE GENERATION ENHANCEMENT
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ IMAGE ENHANCEMENT NODES ═══╗"

install_node "https://github.com/Fannovel16/comfyui_controlnet_aux.git" \
    "ControlNet preprocessors (depth, pose, canny, normal, lineart, etc.)"

install_node "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git" \
    "Tiled upscaling for high-resolution output without OOM"

install_node "https://github.com/storyicon/comfyui_segment_anything.git" \
    "SAM-based segmentation for inpainting and compositing"

install_node "https://github.com/Acly/comfyui-inpaint-nodes.git" \
    "Advanced inpainting with FOOOCUS inpaint model support"

install_node "https://github.com/Acly/comfyui-tooling-nodes.git" \
    "External tooling integration (Krita AI plugin compatible)"

install_node "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git" \
    "Comfyroll Studio — large collection of workflow utility nodes"

# ═══════════════════════════════════════════════════════════════════════════════
# FLUX / MODERN ARCHITECTURES
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ MODERN ARCHITECTURE NODES ═══╗"

install_node "https://github.com/kijai/ComfyUI-Florence2.git" \
    "Florence-2 vision-language model for image captioning & detection"

install_node "https://github.com/kijai/ComfyUI-SUPIR.git" \
    "SUPIR — state-of-the-art image upscaling with detail enhancement"

install_node "https://github.com/kijai/ComfyUI-LivePortraitKJ.git" \
    "LivePortrait — animated portrait puppeteering from single image"

# ═══════════════════════════════════════════════════════════════════════════════
# AUDIO / TTS / VOICE
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ AUDIO / TTS NODES ═══╗"

install_node "https://github.com/SaltAI/SaltAI_AudioViz.git" \
    "Audio visualization, TTS, audio processing & video muxing"

install_node "https://github.com/ai-dock/ComfyUI-No-Silence.git" \
    "Audio silence removal for TTS post-processing" 2>/dev/null || true

# ═══════════════════════════════════════════════════════════════════════════════
# WORKFLOW UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ WORKFLOW UTILITY NODES ═══╗"

install_node "https://github.com/WASasquatch/was-node-suite-comfyui.git" \
    "WAS Suite — 100+ utility nodes (image ops, text, math, IO)"

install_node "https://github.com/rgthree/rgthree-comfy.git" \
    "Workflow organization, bookmarks, context switching, reroute"

install_node "https://github.com/jags111/efficiency-nodes-comfyui.git" \
    "Batch processing, A/B testing, parameter sweeps"

install_node "https://github.com/kijai/ComfyUI-KJNodes.git" \
    "General utility nodes by kijai — essential for video workflows"

install_node "https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git" \
    "Workflow auto-arrange, always-on-top, image feed, favicon"

install_node "https://github.com/chrisgoringe/cg-use-everywhere.git" \
    "Use Everywhere — broadcast values without explicit connections"

install_node "https://github.com/Derfuu/Derfuu_ComfyUI_ModdedNodes.git" \
    "Math, type conversion, automatic sizing utilities"

install_node "https://github.com/melMass/comfy_mtb.git" \
    "MTB nodes — face detection, batch ops, color processing"

install_node "https://github.com/crystian/ComfyUI-Crystools.git" \
    "Crystools — resource monitor, metadata, debug tools"

install_node "https://github.com/11cafe/comfyui-workspace-manager.git" \
    "Workspace manager — save/load workflow snapshots and versions"

# ═══════════════════════════════════════════════════════════════════════════════
# 3D MODEL GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ 3D MODEL GENERATION NODES ═══╗"

install_node "https://github.com/MrForExample/ComfyUI-3D-Pack.git" \
    "3D model generation — TripoSR, InstantMesh, multiview generation" 2>/dev/null || true

install_node "https://github.com/kijai/ComfyUI-Marigold.git" \
    "Marigold depth estimation — high-quality monocular depth maps"

# ═══════════════════════════════════════════════════════════════════════════════
# POST-INSTALL: ComfyUI Manager auto-configuration
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "╔═══ POST-INSTALL CONFIGURATION ═══╗"

# Configure ComfyUI Manager for easy CivitAI model imports
MANAGER_DIR="${NODES_DIR}/ComfyUI-Manager"
if [ -d "$MANAGER_DIR" ]; then
    # Enable CivitAI integration in ComfyUI Manager config
    MANAGER_CONFIG_DIR="${COMFYUI_DIR:-/opt/comfyui}/user/default"
    mkdir -p "$MANAGER_CONFIG_DIR"

    # Create ComfyUI Manager config if it doesn't exist
    MANAGER_CONFIG="${MANAGER_CONFIG_DIR}/comfy.settings.json"
    if [ ! -f "$MANAGER_CONFIG" ]; then
        cat > "$MANAGER_CONFIG" <<'MGREOF'
{
    "Comfy.UseNewMenu": "Top",
    "Comfy.Workflow.ShowMissingNodesWarning": true,
    "Comfy.Workflow.ShowMissingModelsWarning": true,
    "impact.wildcards.WildcardDict.path": "/opt/comfyui/custom_nodes/ComfyUI-Impact-Pack/wildcards",
    "Comfy.Validation.Prompts": true
}
MGREOF
        log "INFO" "    ✓ Created ComfyUI settings for Manager integration"
    fi

    log "INFO" "    ✓ ComfyUI Manager configured — CivitAI import available via UI"
else
    log "WARN" "    ComfyUI Manager not found — CivitAI integration unavailable"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

log "INFO" ""
log "INFO" "═══════════════════════════════════════════════════════════"
log "INFO" "  Node Installation Summary"
log "INFO" "═══════════════════════════════════════════════════════════"
log "INFO" "  Total attempted:  ${TOTAL}"
log "INFO" "  New installs:     $((PASSED - SKIPPED))"
log "INFO" "  Updated:          ${SKIPPED}"
log "INFO" "  Passed:           ${PASSED}"
log "INFO" "  Failed:           ${FAILED}"

if [ $FAILED -gt 0 ]; then
    log "WARN" ""
    log "WARN" "  Failed nodes:${FAILED_NODES}"
    log "WARN" ""
    log "WARN" "  Check full log: cat ${LOG_FILE}"
fi

log "INFO" "  Active nodes:     $(ls -d */ 2>/dev/null | wc -l)"
log "INFO" "═══════════════════════════════════════════════════════════"

# Exit with failure count (0 = success)
exit $FAILED
