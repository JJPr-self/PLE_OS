#!/bin/bash
# ================================================================
# PLEASUREDAI OS — Custom Node Installer
# Wan 2.2 + Motion Control + Pose + Rigging + Video Pipeline
#
# Installed during Docker build. Each node is isolated so failures
# in optional/experimental nodes won't break the build.
# ================================================================

NODES_DIR="${CUSTOM_NODES_DIR:-/opt/comfyui/custom_nodes}"
mkdir -p "$NODES_DIR"
cd "$NODES_DIR" || exit 1

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/echo

install_node() {
    local REPO_URL="$1"
    local DIR_NAME="$(basename "$REPO_URL" .git)"
    echo "Installing: $DIR_NAME"
    if [ ! -d "$DIR_NAME" ]; then
        git clone --depth 1 "$REPO_URL" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "  ✗ Failed to clone $DIR_NAME"
            return 1
        fi
        if [ -f "${DIR_NAME}/requirements.txt" ]; then
            pip install -r "${DIR_NAME}/requirements.txt" --quiet 2>/dev/null || true
        fi
        if [ -f "${DIR_NAME}/install.py" ]; then
            python "${DIR_NAME}/install.py" 2>/dev/null || true
        fi
        echo "  ✓ $DIR_NAME installed"
    else
        echo "  ~ $DIR_NAME already present"
    fi
}

# ═══════════════════════════════════════════════════
# CORE — Manager + essential utilities
# ═══════════════════════════════════════════════════
echo "=== CORE ==="
install_node "https://github.com/ltdrdata/ComfyUI-Manager.git"

# ═══════════════════════════════════════════════════
# VIDEO GENERATION — Wan 2.1/2.2, Video Helper, GGUF
# ═══════════════════════════════════════════════════
echo "=== VIDEO GENERATION ==="
install_node "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
install_node "https://github.com/city96/ComfyUI-GGUF"
install_node "https://github.com/kijai/ComfyUI-KJNodes.git"

# ═══════════════════════════════════════════════════
# MOTION CONTROL — Wan Fun Control, ControlNet, Pose
# ═══════════════════════════════════════════════════
echo "=== MOTION CONTROL / CONTROLNET ==="
install_node "https://github.com/Fannovel16/comfyui_controlnet_aux"
install_node "https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet"
install_node "https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved"
install_node "https://github.com/kijai/ComfyUI-WanFunControlWrapper" || true

# ═══════════════════════════════════════════════════
# FACE / IDENTITY — IPAdapter, Reactor
# ═══════════════════════════════════════════════════
echo "=== FACE / IDENTITY ==="
install_node "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"
install_node "https://github.com/Gourieff/comfyui-reactor-node" || true

# ═══════════════════════════════════════════════════
# 3D RIGGING / POSE ESTIMATION — UniRig, 3D Pack
# ═══════════════════════════════════════════════════
echo "=== 3D RIGGING / POSE ==="
install_node "https://github.com/MrForExample/ComfyUI-UniRig" || true
install_node "https://github.com/MrForExample/ComfyUI-3D-Pack" || true

# ═══════════════════════════════════════════════════
# MEME / REEL / AUDIO — TTS, Sound, Layering
# ═══════════════════════════════════════════════════
echo "=== MEME / AUDIO ==="
install_node "https://github.com/longboarder-dev/ComfyUI-F5-TTS" || true
install_node "https://github.com/vladmandic/comfyui-audio" || true
install_node "https://github.com/chibiace/ComfyUI-LayerStyle" || true
install_node "https://github.com/omar92/ComfyUI-Meme-Generator" || true

# ═══════════════════════════════════════════════════
# WORKFLOW UTILITIES
# ═══════════════════════════════════════════════════
echo "=== WORKFLOW UTILITIES ==="
install_node "https://github.com/WASasquatch/was-node-suite-comfyui.git"
install_node "https://github.com/rgthree/rgthree-comfy.git"

echo "=== INSTALLATION COMPLETE ==="
exit 0
