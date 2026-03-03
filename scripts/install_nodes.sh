#!/bin/bash
# ================================================================
# PLEASUREDAI OS — Bare Minimum Node Installer (Wan 2.2 focus)
# Reduced to prevent 1-hour compile timeouts in Docker build
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
        git clone --depth 1 "$REPO_URL"
        if [ -f "${DIR_NAME}/requirements.txt" ]; then
            pip install -r "${DIR_NAME}/requirements.txt" --quiet
        fi
    fi
}

echo "=== CORE ==="
install_node "https://github.com/ltdrdata/ComfyUI-Manager.git"

echo "=== VIDEO GENERATION ==="
install_node "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
install_node "https://github.com/city96/ComfyUI-GGUF"

echo "=== FACE SWAP (Bare Minimum) ==="
# Using alternative clone for IPAdapter as Reactor fails
install_node "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"

echo "=== WORKFLOW UTILITIES ==="
install_node "https://github.com/WASasquatch/was-node-suite-comfyui.git"
install_node "https://github.com/rgthree/rgthree-comfy.git"
install_node "https://github.com/kijai/ComfyUI-KJNodes.git"

echo "=== INSTALLATION COMPLETE ==="
exit 0
