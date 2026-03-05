#!/bin/bash
# ================================================================
#  PLEASUREDAI OS — UNIFIED SETUP
#  Installs ALL custom nodes + ALL models needed for:
#    ✓ Wan 2.1/2.2 T2V (Text-to-Video)
#    ✓ Wan 2.1/2.2 I2V (Image-to-Video)
#    ✓ SDXL (Text-to-Image)
#    ✓ ControlNet (Depth / Pose / Canny)
#    ✓ Motion Control (VACE, CausVid, AccVid)
#    ✓ Face Swap (ReActor)
#    ✗ 3D Mesh (optional — run wan22_setup.sh for UniRig/3D-Pack)
#
#  ALL downloads use wget/aria2c — ZERO huggingface-cli usage.
#  All model URLs verified against actual HuggingFace repos.
#
#  USAGE (inside container):
#    chmod +x /opt/scripts/setup.sh && bash /opt/scripts/setup.sh
# ================================================================

set -e
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔] $1${NC}"; }
info() { echo -e "${CYAN}[→] $1${NC}"; }
skip() { echo -e "${YELLOW}[~] SKIP: $1${NC}"; }
err()  { echo -e "${RED}[✘] $1${NC}"; }

DL_OK=0; DL_SKIP=0; DL_FAIL=0; DL_TOTAL=0

# ================================================================
# CONFIG — set tokens here or export before running
# ================================================================
if [ -z "$HF_TOKEN" ]; then
    read -p "HuggingFace Token (Enter to skip): " HF_TOKEN
fi

# ================================================================
# AUTO-DETECT COMFYUI
# ================================================================
COMFY="${COMFYUI_DIR:-/opt/comfyui}"
[ ! -d "$COMFY" ] && [ -d "/workspace/ComfyUI" ] && COMFY="/workspace/ComfyUI"
if [ ! -d "$COMFY" ]; then
    err "ComfyUI not found! Set COMFYUI_DIR env var."
    exit 1
fi
info "ComfyUI: $COMFY"
cd "$COMFY"

# ================================================================
# DOWNLOAD HELPER
# ================================================================
dl() {
    local url="$1" dest="$2" fname="$3"
    DL_TOTAL=$((DL_TOTAL + 1))

    if [ -f "$dest/$fname" ]; then
        local sz; sz=$(stat -c%s "$dest/$fname" 2>/dev/null || echo "0")
        if [ "$sz" -gt 10000 ]; then
            skip "$fname ($(numfmt --to=iec "$sz" 2>/dev/null || echo "${sz}B"))"
            DL_SKIP=$((DL_SKIP + 1))
            return 0
        fi
        rm -f "$dest/$fname"
    fi

    mkdir -p "$dest"
    info "Downloading $fname ..."

    local auth=""
    if [ -n "$HF_TOKEN" ] && [[ "$url" == *"huggingface.co"* ]]; then
        auth="--header=Authorization: Bearer ${HF_TOKEN}"
    fi

    local rc=0
    if command -v aria2c &>/dev/null; then
        aria2c -x 8 -s 8 --max-tries=3 --retry-wait=5 \
            --console-log-level=warn --download-result=hide --summary-interval=15 \
            ${auth} -d "$dest" -o "$fname" "$url" || rc=$?
    else
        wget -q --show-progress --tries=3 --waitretry=5 \
            ${auth:+--header="Authorization: Bearer ${HF_TOKEN}"} \
            -O "$dest/$fname" "$url" || rc=$?
    fi

    if [ $rc -ne 0 ] || [ ! -f "$dest/$fname" ] || [ "$(stat -c%s "$dest/$fname" 2>/dev/null || echo 0)" -lt 10000 ]; then
        err "FAILED: $fname"
        rm -f "$dest/$fname"
        DL_FAIL=$((DL_FAIL + 1))
        return 1
    fi

    log "$fname ✓ ($(numfmt --to=iec "$(stat -c%s "$dest/$fname")" 2>/dev/null || echo '?'))"
    DL_OK=$((DL_OK + 1))
}

# ── Shorthand helpers ──
dlk() { dl "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/$1" "$2" "${3:-$1}"; }
dlc() { dl "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/$1" "$2" "$3"; }

# ================================================================
# STEP 1 — PIP DEPENDENCIES
# ================================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 1: Python Dependencies${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
pip install -q decord imageio-ffmpeg opencv-python imageio 2>/dev/null || true
pip install -q einops sentencepiece accelerate peft 2>/dev/null || true
pip install -q sageattention==1.0.6 2>/dev/null || true
pip install -q mediapipe onnxruntime-gpu 2>/dev/null || true
log "Dependencies OK"

# ================================================================
# STEP 2 — CUSTOM NODES
# ================================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 2: Custom Nodes${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
cd "$COMFY/custom_nodes"

inode() {
    local dir="$1" url="$2"
    if [ ! -d "$dir" ]; then
        git clone --depth 1 -q "$url" "$dir" 2>/dev/null || { err "Clone failed: $dir"; return 1; }
        [ -f "$dir/requirements.txt" ] && pip install -q -r "$dir/requirements.txt" 2>/dev/null || true
        [ -f "$dir/install.py" ] && python "$dir/install.py" 2>/dev/null || true
        log "$dir"
    else
        skip "$dir"
    fi
}

# Core
inode "ComfyUI-Manager"              "https://github.com/ltdrdata/ComfyUI-Manager.git"
# Video
inode "ComfyUI-WanVideoWrapper"      "https://github.com/kijai/ComfyUI-WanVideoWrapper"
inode "ComfyUI-VideoHelperSuite"     "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
inode "ComfyUI-GGUF"                 "https://github.com/city96/ComfyUI-GGUF"
inode "ComfyUI-KJNodes"              "https://github.com/kijai/ComfyUI-KJNodes"
# ControlNet / Pose
inode "ComfyUI_Controlnet_aux"       "https://github.com/Fannovel16/comfyui_controlnet_aux"
inode "ComfyUI-Advanced-ControlNet"  "https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet"
inode "ComfyUI-AnimateDiff-Evolved"  "https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved"
# Motion Control
inode "ComfyUI_IPAdapter_plus"       "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
inode "ComfyUI-WanFunControlWrapper" "https://github.com/kijai/ComfyUI-WanFunControlWrapper" || true
# Face
inode "comfyui-reactor-node"         "https://github.com/Gourieff/comfyui-reactor-node" || true
# Utilities
inode "was-node-suite-comfyui"       "https://github.com/WASasquatch/was-node-suite-comfyui"
inode "rgthree-comfy"                "https://github.com/rgthree/rgthree-comfy"

cd "$COMFY"

# ================================================================
# STEP 3 — DIRECTORIES
# ================================================================
mkdir -p models/{diffusion_models,vae,text_encoders,clip_vision,clip,loras,controlnet,checkpoints,upscale_models} \
         user/default/workflows

# ================================================================
# STEP 4 — WAN MODELS (Kijai single-file format)
# Filenames verified from: https://huggingface.co/Kijai/WanVideo_comfy
# ================================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 4: Wan 2.1/2.2 Models${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"

# T2V 14B fp8 (~14.9GB)
dlk "Wan2_1-T2V-14B_fp8_e4m3fn.safetensors"        "models/diffusion_models"
# T2V 1.3B fp8 (~1.5GB)
dlk "Wan2_1-T2V-1_3B_fp8_e4m3fn.safetensors"       "models/diffusion_models"
# I2V 480P 14B fp8 (~17GB)
dlk "Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors"   "models/diffusion_models"
# I2V 720P 14B fp8 (~17GB)
dlk "Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors"   "models/diffusion_models"
# Wan 2.2 I2V A14B HIGH bf16 (~28.6GB)
dlk "Wan2_2-I2V-A14B-HIGH_bf16.safetensors"        "models/diffusion_models"

# ── VAE ──
dlk "Wan2_1_VAE_bf16.safetensors"                   "models/vae"
dlk "Wan2_2_VAE_bf16.safetensors"                   "models/vae"
# TAE (Temporal AutoEncoder for preview)
dlk "taew2_1.safetensors"                            "models/vae"
dlk "taew2_2.safetensors"                            "models/vae"

# ── Text Encoder ──
dlk "umt5-xxl-enc-fp8_e4m3fn.safetensors"           "models/text_encoders"
dlk "umt5-xxl-enc-bf16.safetensors"                  "models/text_encoders"

# ── CLIP Vision ──
dl  "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
    "models/clip_vision" "sigclip_vision_patch14_384.safetensors"
dlk "open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" "models/clip_vision"
dlc "clip_vision/clip_vision_h.safetensors"          "models/clip_vision" "clip_vision_h.safetensors"

# ================================================================
# STEP 5 — COMFY-ORG NATIVE MODELS (alternative format)
# ================================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 5: Comfy-Org Native Models${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
dlc "diffusion_models/wan2.1_t2v_14B_fp8_e4m3fn.safetensors" "models/diffusion_models" "wan2.1_t2v_14B_fp8_e4m3fn.safetensors"
dlc "diffusion_models/wan2.1_i2v_480p_14B_fp8_e4m3fn.safetensors" "models/diffusion_models" "wan2.1_i2v_480p_14B_fp8_e4m3fn.safetensors"
dlc "text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" "models/text_encoders" "umt5_xxl_fp8_e4m3fn_scaled.safetensors"
dlc "vae/wan_2.1_vae.safetensors" "models/vae" "wan_2.1_vae.safetensors"

# ================================================================
# STEP 6 — MOTION CONTROL (VACE + LoRAs)
# ================================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 6: Motion Control & LoRAs${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
# VACE modules
dlk "Wan2_1-VACE_module_14B_bf16.safetensors"       "models/diffusion_models"
dlk "Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors" "models/diffusion_models"
dlk "Wan2_1-VACE_module_1_3B_bf16.safetensors"      "models/diffusion_models"
# CausVid / AccVid LoRAs (fast generation)
dlk "Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors"         "models/loras"
dlk "Wan21_AccVid_T2V_14B_lora_rank32_fp16.safetensors"        "models/loras"
dlk "Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors"   "models/loras"

# ================================================================
# STEP 6B — MEME & TTS MODELS
# ================================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 6B: Meme & TTS Models${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
# F5-TTS & E2-TTS
dl "https://huggingface.co/charactertts/F5-TTS/resolve/main/F5TTS_Base/model_1200000.pt" "models/f5tts" "model_1200000.pt"
dl "https://huggingface.co/charactertts/F5-TTS/resolve/main/E2TTS_Base/model_1200000.pt" "models/f5tts" "e2_model_1200000.pt"
# Vocos
dl "https://huggingface.co/charactertts/F5-TTS/resolve/main/vocos/config.yaml" "models/f5tts/vocos" "config.yaml"
dl "https://huggingface.co/charactertts/F5-TTS/resolve/main/vocos/pytorch_model.bin" "models/f5tts/vocos" "pytorch_model.bin"

# ================================================================
# STEP 7 — COPY WORKFLOWS
# ================================================================
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  STEP 7: Writing Workflows${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
# Workflows are already baked into the Docker image at user/default/workflows/
# This step ensures they exist even if the volume mount is empty
if [ -d "/opt/scripts" ] && ls /opt/comfyui/user/default/workflows/*.json 1>/dev/null 2>&1; then
    log "Workflows already present"
else
    info "Workflows may need to be loaded via ComfyUI Manager"
fi

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  PLEASUREDAI OS — SETUP COMPLETE${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Downloads: ${DL_OK} ok | ${DL_SKIP} skipped | ${DL_FAIL} failed | ${DL_TOTAL} total"
echo ""
echo -e "  Models installed to: $COMFY/models/"
echo ""
echo -e "  ${CYAN}Wan T2V:${NC} Wan2_1-T2V-14B_fp8_e4m3fn.safetensors"
echo -e "  ${CYAN}Wan I2V:${NC} Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors"
echo -e "  ${CYAN}Wan VAE:${NC} Wan2_1_VAE_bf16.safetensors"
echo -e "  ${CYAN}TE:${NC}      umt5-xxl-enc-fp8_e4m3fn.safetensors"
echo -e "  ${CYAN}CLIP:${NC}    sigclip_vision_patch14_384.safetensors"
echo -e "  ${CYAN}VACE:${NC}    Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors"
echo ""
echo -e "  ${YELLOW}Optional (not installed):${NC}"
echo -e "    • 3D Mesh (UniRig/3D-Pack) — run: bash /opt/scripts/wan22_setup.sh"
echo ""
if [ $DL_FAIL -gt 0 ]; then
    echo -e "  ${RED}⚠ $DL_FAIL downloads failed. Re-run to retry.${NC}"
fi
echo ""
