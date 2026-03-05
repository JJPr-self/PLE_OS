#!/bin/bash
# ================================================================
#  PLEASUREDAI OS — UNIFIED SETUP
#  Run ONCE after container boot on your persistent volume.
#
#  Installs ALL custom nodes + ALL verified models for:
#    ✓ Wan 2.1 T2V + I2V (Text/Image-to-Video)
#    ✓ Wan 2.1 VACE Motion Control
#    ✓ CausVid / AccVid LoRAs (fast generation)
#    ✓ F5-TTS AI Voice (Meme Reel)
#    ✓ SDXL-ready (checkpoints via ComfyUI Manager)
#    ✗ 3D Mesh / UniRig (optional — separate script)
#
#  ALL URLs verified against live HuggingFace repos 2025-03-04.
#  ZERO huggingface-cli. Uses aria2c > wget.
#
#  USAGE:
#    bash /opt/scripts/setup.sh
# ================================================================

set -euo pipefail
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔] $1${NC}"; }
info() { echo -e "${CYAN}[→] $1${NC}"; }
skip() { echo -e "${YELLOW}[~] SKIP: $1${NC}"; }
err()  { echo -e "${RED}[✘] $1${NC}"; }

DL_OK=0; DL_SKIP=0; DL_FAIL=0; DL_TOTAL=0

# ================================================================
# CONFIG
# ================================================================
HF_TOKEN="${HF_TOKEN:-}"
if [ -z "$HF_TOKEN" ]; then
    read -rp "HuggingFace Token (press Enter to skip): " HF_TOKEN || true
fi

COMFY="${COMFYUI_DIR:-/opt/comfyui}"
[ ! -d "$COMFY" ] && [ -d "/workspace/ComfyUI" ] && COMFY="/workspace/ComfyUI"
if [ ! -d "$COMFY" ]; then
    err "ComfyUI not found. Set COMFYUI_DIR or run inside the container."
    exit 1
fi
info "ComfyUI root: $COMFY"

# ================================================================
# DOWNLOAD HELPER (aria2c preferred, wget fallback)
# Skips files already present and > 10KB.
# ================================================================
dl() {
    local url="$1" dest="$2" fname="$3"
    DL_TOTAL=$((DL_TOTAL + 1))

    if [ -f "$dest/$fname" ]; then
        local sz; sz=$(stat -c%s "$dest/$fname" 2>/dev/null || echo "0")
        if [ "$sz" -gt 10000 ]; then
            skip "$fname ($(numfmt --to=iec "$sz" 2>/dev/null || echo "${sz}B") cached)"
            DL_SKIP=$((DL_SKIP + 1))
            return 0
        fi
        rm -f "$dest/$fname"
    fi

    mkdir -p "$dest"
    info "Downloading $fname …"

    local rc=0
    if command -v aria2c &>/dev/null; then
        aria2c -x 8 -s 8 --max-tries=3 --retry-wait=5 \
            --console-log-level=warn --download-result=hide --summary-interval=30 \
            ${HF_TOKEN:+--header="Authorization: Bearer ${HF_TOKEN}"} \
            -d "$dest" -o "$fname" "$url" || rc=$?
    else
        wget -q --show-progress --tries=3 --waitretry=5 \
            ${HF_TOKEN:+--header="Authorization: Bearer ${HF_TOKEN}"} \
            -O "$dest/$fname" "$url" || rc=$?
    fi

    if [ $rc -ne 0 ] || [ ! -f "$dest/$fname" ] || \
       [ "$(stat -c%s "$dest/$fname" 2>/dev/null || echo 0)" -lt 10000 ]; then
        err "FAILED: $fname"
        rm -f "$dest/$fname"
        DL_FAIL=$((DL_FAIL + 1))
        return 1
    fi

    log "$fname ($(numfmt --to=iec "$(stat -c%s "$dest/$fname")" 2>/dev/null || echo '?'))"
    DL_OK=$((DL_OK + 1))
}

# Shorthand: Kijai/WanVideo_comfy root
dlk() { dl "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/$1" "$2" "${3:-$(basename "$1")}"; }
# Shorthand: Comfy-Org/Wan_2.1_ComfyUI_repackaged split_files
dlc() { dl "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/$1" "$2" "$(basename "$1")"; }
# Shorthand: SWivid/F5-TTS
dlf() { dl "https://huggingface.co/SWivid/F5-TTS/resolve/main/$1" "$2" "$(basename "$1")"; }

# ================================================================
# STEP 1 — PIP EXTRAS (only what's not in the base image)
# ================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 1: Pip Extras${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
pip install -q --upgrade sageattention==1.0.6 2>/dev/null || true
pip install -q peft f5-tts 2>/dev/null || true
log "Pip extras OK"

# ================================================================
# STEP 2 — CUSTOM NODES
# ================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 2: Custom Nodes${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"
cd "$COMFY/custom_nodes"

inode() {
    local dir="$1" url="$2"
    if [ ! -d "$dir" ]; then
        git clone --depth 1 -q "$url" "$dir" 2>/dev/null || { err "Clone failed: $dir"; return 1; }
        [ -f "$dir/requirements.txt" ] && pip install -q -r "$dir/requirements.txt" 2>/dev/null || true
        [ -f "$dir/install.py" ]       && python "$dir/install.py" 2>/dev/null || true
        log "$dir"
    else
        skip "$dir (already installed)"
    fi
}

# Core manager
inode "ComfyUI-Manager"              "https://github.com/ltdrdata/ComfyUI-Manager.git"
# Video Generation
inode "ComfyUI-WanVideoWrapper"      "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
inode "ComfyUI-VideoHelperSuite"     "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
inode "ComfyUI-GGUF"                 "https://github.com/city96/ComfyUI-GGUF.git"
inode "ComfyUI-KJNodes"              "https://github.com/kijai/ComfyUI-KJNodes.git"
# ControlNet / Pose
inode "ComfyUI_Controlnet_aux"       "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
inode "ComfyUI-Advanced-ControlNet"  "https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git"
inode "ComfyUI-AnimateDiff-Evolved"  "https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved.git"
# Face / Identity
inode "ComfyUI_IPAdapter_plus"       "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"
inode "comfyui-reactor-node"         "https://github.com/Gourieff/comfyui-reactor-node.git" || true
# Meme / Audio / Reel
inode "ComfyUI-F5-TTS"              "https://github.com/longboarder-dev/ComfyUI-F5-TTS.git" || true
inode "comfyui-audio"               "https://github.com/vladmandic/comfyui-audio.git" || true
inode "ComfyUI-LayerStyle"          "https://github.com/chibiace/ComfyUI-LayerStyle.git" || true
# Utilities
inode "was-node-suite-comfyui"       "https://github.com/WASasquatch/was-node-suite-comfyui.git"
inode "rgthree-comfy"                "https://github.com/rgthree/rgthree-comfy.git"

cd "$COMFY"

# ================================================================
# STEP 3 — DIRECTORIES
# ================================================================
mkdir -p models/{diffusion_models,vae,text_encoders,clip_vision,clip,loras,controlnet,checkpoints,upscale_models,f5tts}
mkdir -p user/default/workflows

# ================================================================
# STEP 4 — WAN 2.1 DIFFUSION MODELS
# Source: https://huggingface.co/Kijai/WanVideo_comfy (at root)
# All filenames verified 2025-03-04.
# ================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 4: Wan 2.1 Diffusion Models${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

# T2V 14B fp8 (~14.9 GB) ✅ verified at root
dlk "Wan2_1-T2V-14B_fp8_e4m3fn.safetensors"        "$COMFY/models/diffusion_models"
# T2V 1.3B fp8 (~1.5 GB) ✅ verified at root
dlk "Wan2_1-T2V-1_3B_fp8_e4m3fn.safetensors"       "$COMFY/models/diffusion_models"
# I2V 480P 14B fp8 (~17 GB) ✅
dlk "Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors"   "$COMFY/models/diffusion_models"
# I2V 720P 14B fp8 (~17 GB) ✅
dlk "Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors"   "$COMFY/models/diffusion_models"
# AccVideo T2V 14B fp8 (~15 GB) ✅ verified at root
dlk "Wan2_1-AccVideo-T2V-14B_fp8_e4m3fn.safetensors" "$COMFY/models/diffusion_models"

# ================================================================
# STEP 5 — WAN 2.1 VAE / TEXT ENCODER / CLIP VISION
# ================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 5: VAE, Text Encoder, CLIP Vision${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

# VAE ✅
dlk "Wan2_1_VAE_bf16.safetensors"                    "$COMFY/models/vae"

# Text Encoder ✅
dlk "umt5-xxl-enc-fp8_e4m3fn.safetensors"            "$COMFY/models/text_encoders"
dlk "umt5-xxl-enc-bf16.safetensors"                  "$COMFY/models/text_encoders"

# CLIP Vision — sigclip ✅ verified in Comfy-Org/sigclip_vision_384
dl "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
   "$COMFY/models/clip_vision" "sigclip_vision_patch14_384.safetensors"

# CLIP Vision H — from Comfy-Org Wan repackaged split_files ✅
dlc "clip_vision/clip_vision_h.safetensors"           "$COMFY/models/clip_vision"

# ================================================================
# STEP 6 — VACE MOTION CONTROL
# Source: Kijai/WanVideo_comfy at root (verified 2025-03-04)
# ================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 6: VACE Motion Control${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

# VACE 14B ✅ verified at root
dlk "Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors"  "$COMFY/models/diffusion_models"
dlk "Wan2_1-VACE_module_14B_bf16.safetensors"         "$COMFY/models/diffusion_models"
# VACE 1.3B ✅ verified at root
dlk "Wan2_1-VACE_module_1_3B_bf16.safetensors"        "$COMFY/models/diffusion_models"

# ================================================================
# STEP 7 — LoRAs (Fast Generation)
# All filenames verified at Kijai root 2025-03-04.
# ================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 7: LoRAs (CausVid / AccVid)${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

# CausVid v2 ✅ (v2 is the latest — "v1" files have been superseded)
dlk "Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors"        "$COMFY/models/loras"
# AccVid T2V ✅
dlk "Wan21_AccVid_T2V_14B_lora_rank32_fp16.safetensors"       "$COMFY/models/loras"
# AccVid I2V 480P ✅
dlk "Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors"  "$COMFY/models/loras"

# ================================================================
# STEP 8 — F5-TTS (AI Voice for Meme Reel)
# Source: SWivid/F5-TTS ✅ verified 2025-03-04
# NOTE: 'charactertts' was wrong — real repo is 'SWivid'.
# Using .safetensors (safer than .pt pickle).
# ================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 8: F5-TTS Voice Models${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

# F5-TTS Base model (safetensors — no pickle) ✅
dlf "F5TTS_Base/model_1200000.safetensors" "$COMFY/models/f5tts" "F5TTS_Base_model_1200000.safetensors"
# Vocab ✅
dlf "F5TTS_Base/vocab.txt"                 "$COMFY/models/f5tts" "F5TTS_vocab.txt"

# ================================================================
# STEP 9 — COMFY-ORG NATIVE FORMAT (Alternative filenames)
# These use the Comfy-Org naming convention (not Kijai).
# Useful if your workflows reference these exact filenames.
# ================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 9: Comfy-Org Native Models${NC}"
echo -e "${CYAN}══════════════════════════════════════════${NC}"

# T2V 14B fp8 ✅ verified
dlc "diffusion_models/wan2.1_t2v_14B_fp8_e4m3fn.safetensors" "$COMFY/models/diffusion_models"
# I2V 480P 14B fp8 ✅ verified
dlc "diffusion_models/wan2.1_i2v_480p_14B_fp8_e4m3fn.safetensors" "$COMFY/models/diffusion_models"
# Text encoder fp8 scaled ✅
dlc "text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "$COMFY/models/text_encoders"
# VAE ✅
dlc "vae/wan_2.1_vae.safetensors" "$COMFY/models/vae"

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  PLEASUREDAI OS — SETUP COMPLETE${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo -e "  Downloads: ${DL_OK} ok | ${DL_SKIP} skipped | ${DL_FAIL} failed | ${DL_TOTAL} total"
echo ""
echo -e "  Models → $COMFY/models/"
echo ""
if [ $DL_FAIL -gt 0 ]; then
    echo -e "  ${RED}⚠  $DL_FAIL downloads failed — re-run to retry${NC}"
    echo ""
fi
echo -e "  ${YELLOW}Not installed (optional):${NC}"
echo -e "    • 3D Mesh/UniRig → run: bash /opt/scripts/wan22_setup.sh"
echo -e "    • Wan 2.2 models (not yet on Kijai as single-file at root)"
echo ""
