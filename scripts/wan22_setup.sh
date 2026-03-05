#!/bin/bash
# ================================================================
#  WAN 2.2 — MODELS + WORKFLOWS + MOTION CONTROL
#  For Vast.ai ComfyUI template (ComfyUI already running)
#  Skips anything already present. Zero HuggingFace CLI usage.
#  T2V + I2V | LoRA-ready | Motion Control | Pose Estimation
#
#  ALL downloads use wget direct URLs — no huggingface-cli.
# ================================================================
# USAGE:
#   chmod +x /opt/scripts/wan22_setup.sh && bash /opt/scripts/wan22_setup.sh
# ================================================================

set -e
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✔] $1${NC}"; }
info() { echo -e "${CYAN}[→] $1${NC}"; }
skip() { echo -e "${YELLOW}[~] SKIP: $1 already exists${NC}"; }
err()  { echo -e "${RED}[✘] $1${NC}"; }

# ================================================================
# COUNTERS
# ================================================================
DL_TOTAL=0
DL_PASSED=0
DL_SKIPPED=0
DL_FAILED=0

# ================================================================
# ▼▼▼ YOUR CONFIG — EDIT THIS SECTION ONLY ▼▼▼
# ================================================================

# Read tokens interactively if not set
if [ -z "$HF_TOKEN" ]; then
    echo -e "${YELLOW}No HF_TOKEN found in environment.${NC}"
    read -p "Enter your HuggingFace Token (HF_TOKEN) [Press Enter to skip]: " HF_TOKEN
fi

if [ -z "$CIVITAI_API_KEY" ]; then
    echo -e "${YELLOW}No CIVITAI_API_KEY found in environment.${NC}"
    read -p "Enter your Civitai API Key (CIVITAI_API_KEY) [Press Enter to skip]: " CIVITAI_API_KEY
fi

# ── PASTE CIVITAI DOWNLOAD URLS DIRECTLY ──────────────────────
LORAS=(
  "https://civitai.com/api/download/models/368206?type=Model&format=SafeTensor"
)
# ▲▲▲ END OF CONFIG ▲▲▲

# ================================================================
# AUTO-DETECT COMFYUI PATH
# ================================================================
COMFY="/opt/comfyui"
if [ ! -d "$COMFY" ]; then
  err "ComfyUI not found at $COMFY. Check your instance volume mappings."
  [ -d "/workspace/ComfyUI" ] && COMFY="/workspace/ComfyUI"
fi
info "ComfyUI targeted at: $COMFY"
cd "$COMFY"

# ================================================================
# DOWNLOAD HELPER — wget only, NO huggingface-cli
# ================================================================
dl() {
  local url="$1" dest="$2" fname="$3"
  DL_TOTAL=$((DL_TOTAL + 1))
  if [ -f "$dest/$fname" ]; then
    local size
    size=$(stat -c%s "$dest/$fname" 2>/dev/null || echo "0")
    if [ "$size" -gt 1000 ]; then
      skip "$fname ($(numfmt --to=iec "$size" 2>/dev/null || echo '?'))"
      DL_SKIPPED=$((DL_SKIPPED + 1))
      return 0
    fi
    # File exists but is too small (likely corrupted/partial)
    rm -f "$dest/$fname"
  fi
  mkdir -p "$dest"
  info "Downloading $fname ..."

  # Build auth header for HuggingFace if token is available
  local auth_args=""
  if [ -n "$HF_TOKEN" ] && [[ "$url" == *"huggingface.co"* ]]; then
    auth_args="--header=Authorization: Bearer ${HF_TOKEN}"
  fi

  local rc=0
  if command -v aria2c &>/dev/null; then
    aria2c -x 8 -s 8 --max-tries=3 --retry-wait=5 \
      --console-log-level=warn \
      --download-result=hide \
      --summary-interval=15 \
      ${auth_args} \
      -d "$dest" -o "$fname" \
      "$url" || rc=$?
  else
    wget -q --show-progress --tries=3 --waitretry=5 \
      ${auth_args:+--header="Authorization: Bearer ${HF_TOKEN}"} \
      -O "$dest/$fname" "$url" || rc=$?
  fi

  if [ $rc -ne 0 ]; then
    err "FAILED: $fname (exit $rc)"
    rm -f "$dest/$fname"
    DL_FAILED=$((DL_FAILED + 1))
    return 1
  fi

  # Verify the file exists and isn't empty
  if [ ! -f "$dest/$fname" ] || [ "$(stat -c%s "$dest/$fname" 2>/dev/null || echo 0)" -lt 1000 ]; then
    err "$fname: File missing or too small after download"
    rm -f "$dest/$fname"
    DL_FAILED=$((DL_FAILED + 1))
    return 1
  fi

  local final_size
  final_size=$(stat -c%s "$dest/$fname" 2>/dev/null || echo "0")
  log "$fname done ($(numfmt --to=iec "$final_size" 2>/dev/null || echo '?'))"
  DL_PASSED=$((DL_PASSED + 1))
  return 0
}

# ── Shorthand: download from Kijai/WanVideo_comfy ──
dl_kijai() {
  local file="$1" dest_dir="$2" dest_name="${3:-$1}"
  dl "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/${file}" \
     "$dest_dir" "$dest_name"
}

# ── Shorthand: download from Comfy-Org repackaged ──
dl_comfy() {
  local subpath="$1" dest_dir="$2" dest_name="$3"
  dl "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/${subpath}" \
     "$dest_dir" "$dest_name"
}

# ================================================================
# STEP 0 — DEPENDENCIES
# ================================================================
info "Installing dependencies required by Wan2.2 & Video nodes..."
pip install -q decord imageio-ffmpeg opencv-python imageio numpy==1.26.4
pip install -q diffusers transformers accelerate peft
pip install -q einops sentencepiece
pip install -q sageattention==1.0.6 || true
pip install -q xformers --index-url https://download.pytorch.org/whl/cu121 || true
pip install -q mediapipe || true
pip install -q onnxruntime-gpu || true
log "Dependency install complete."

# ================================================================
# STEP 1 — HF_TRANSFER for faster downloads (library only, no CLI)
# ================================================================
pip install -q hf_transfer 2>/dev/null || true
export HF_HUB_ENABLE_HF_TRANSFER=1
log "hf_transfer enabled (wget downloads only — no CLI)"

# ================================================================
# STEP 2 — CUSTOM NODES
# ================================================================
info "Checking custom nodes..."
cd "$COMFY/custom_nodes"

install_node() {
  local dir="$1" url="$2"
  if [ ! -d "$dir" ]; then
    info "Installing $dir..."
    git clone --depth 1 -q "$url" "$dir" || { err "Failed to clone $dir"; return 1; }
    if [ -f "$dir/requirements.txt" ]; then
      pip install -q -r "$dir/requirements.txt" 2>/dev/null || true
    fi
    if [ -f "$dir/install.py" ]; then
      python "$dir/install.py" 2>/dev/null || true
    fi
    log "$dir installed"
  else
    skip "$dir"
  fi
}

echo "=== CORE VIDEO NODES ==="
install_node "ComfyUI-WanVideoWrapper"    "https://github.com/kijai/ComfyUI-WanVideoWrapper"
install_node "ComfyUI-VideoHelperSuite"   "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
install_node "ComfyUI-GGUF"              "https://github.com/city96/ComfyUI-GGUF"
install_node "ComfyUI-KJNodes"           "https://github.com/kijai/ComfyUI-KJNodes"

echo "=== CONTROLNET / POSE / DEPTH ==="
install_node "ComfyUI_Controlnet_aux"    "https://github.com/Fannovel16/comfyui_controlnet_aux"
install_node "ComfyUI-Advanced-ControlNet" "https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet"
install_node "ComfyUI-AnimateDiff-Evolved" "https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved"

echo "=== MOTION CONTROL / REFERENCE VIDEO ==="
install_node "ComfyUI_IPAdapter_plus"    "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
install_node "ComfyUI-WanFunControlWrapper" "https://github.com/kijai/ComfyUI-WanFunControlWrapper" || true

echo "=== FACE / IDENTITY ==="
install_node "comfyui-reactor-node"      "https://github.com/Gourieff/comfyui-reactor-node" || true

echo "=== 3D RIGGING / POSE ESTIMATION ==="
install_node "ComfyUI-UniRig"            "https://github.com/MrForExample/ComfyUI-UniRig" || true
install_node "ComfyUI-3D-Pack"           "https://github.com/MrForExample/ComfyUI-3D-Pack" || true

echo "=== WORKFLOW UTILITIES ==="
install_node "was-node-suite-comfyui"    "https://github.com/WASasquatch/was-node-suite-comfyui"
install_node "rgthree-comfy"             "https://github.com/rgthree/rgthree-comfy"
install_node "ComfyUI-Manager"           "https://github.com/ltdrdata/ComfyUI-Manager"

cd "$COMFY"

# ================================================================
# STEP 3 — DIRECTORIES
# ================================================================
mkdir -p models/diffusion_models \
         models/vae \
         models/text_encoders \
         models/clip_vision \
         models/clip \
         models/loras \
         models/controlnet \
         user/default/workflows
log "Directories OK"

# ================================================================
# STEP 4 — MODELS (Kijai single-file format for WanVideoWrapper)
#
# These are the EXACT filenames from https://huggingface.co/Kijai/WanVideo_comfy
# which WanVideoModelLoader expects in models/diffusion_models/
# ================================================================
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  DOWNLOADING WAN 2.1 / 2.2 MODELS (Kijai format)${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

# ── T2V 14B fp8 (~14.9GB) — Text-to-Video main model ──
dl_kijai "Wan2_1-T2V-14B_fp8_e4m3fn.safetensors" \
         "models/diffusion_models"

# ── T2V 1.3B fp8 (~1.5GB) — Lightweight T2V ──
dl_kijai "Wan2_1-T2V-1_3B_fp8_e4m3fn.safetensors" \
         "models/diffusion_models"

# ── I2V 480P 14B fp8 (~17GB) — Image-to-Video 480p ──
dl_kijai "Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors" \
         "models/diffusion_models"

# ── I2V 720P 14B fp8 (~17GB) — Image-to-Video 720p ──
dl_kijai "Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors" \
         "models/diffusion_models"

# ── Wan 2.2 I2V A14B HIGH (~28.6GB) — Wan 2.2 enhanced I2V ──
dl_kijai "Wan2_2-I2V-A14B-HIGH_bf16.safetensors" \
         "models/diffusion_models"

# ── Wan 2.2 VAE (~1.4GB) — Required for Wan 2.2 workflows ──
dl_kijai "Wan2_2_VAE_bf16.safetensors" \
         "models/vae"

# ── Wan 2.1 VAE bf16 (~254MB) — Required for Wan 2.1 workflows ──
dl_kijai "Wan2_1_VAE_bf16.safetensors" \
         "models/vae"

# ── UMT5-XXL Text Encoder fp8 (~6.7GB, Kijai single-file) ──
dl_kijai "umt5-xxl-enc-fp8_e4m3fn.safetensors" \
         "models/text_encoders"

# ── UMT5-XXL Text Encoder bf16 (~11.4GB, Kijai single-file, full precision) ──
dl_kijai "umt5-xxl-enc-bf16.safetensors" \
         "models/text_encoders"

# ── Wan 2.2 TAE (Temporal AutoEncoder) — tiny, used for preview ──
dl_kijai "taew2_2.safetensors" \
         "models/vae"

# ── Wan 2.1 TAE — for 2.1 preview ──
dl_kijai "taew2_1.safetensors" \
         "models/vae"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  DOWNLOADING COMFY-ORG NATIVE MODELS (optional)${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

# ── Comfy-Org Native T2V 14B fp8 (~14.3GB) ──
dl_comfy "diffusion_models/wan2.1_t2v_14B_fp8_e4m3fn.safetensors" \
         "models/diffusion_models" "wan2.1_t2v_14B_fp8_e4m3fn.safetensors"

# ── Comfy-Org Native I2V 480p fp8 (~16.4GB) ──
dl_comfy "diffusion_models/wan2.1_i2v_480p_14B_fp8_e4m3fn.safetensors" \
         "models/diffusion_models" "wan2.1_i2v_480p_14B_fp8_e4m3fn.safetensors"

# ── Comfy-Org Native I2V 720p fp8 (~16.4GB) ──
dl_comfy "diffusion_models/wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors" \
         "models/diffusion_models" "wan2.1_i2v_720p_14B_fp8_e4m3fn.safetensors"

# ── Comfy-Org Native VAE (~254MB) ──
dl_comfy "vae/wan_2.1_vae.safetensors" \
         "models/vae" "wan_2.1_vae.safetensors"

# ── Comfy-Org Native UMT5 FP8 Scaled (~6.7GB) ──
dl_comfy "text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
         "models/text_encoders" "umt5_xxl_fp8_e4m3fn_scaled.safetensors"

# ── Comfy-Org CLIP Vision H (~1.3GB) — for I2V workflows ──
dl_comfy "clip_vision/clip_vision_h.safetensors" \
         "models/clip_vision" "clip_vision_h.safetensors"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  CLIP VISION (SigCLIP for I2V)${NC}  "
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

# ── SigCLIP Vision 384 (~856MB) — for Kijai I2V node ──
dl "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
   "models/clip_vision" "sigclip_vision_patch14_384.safetensors"

# ── Open-CLIP XLM-RoBERTa Visual fp16 (~1.3GB) — for Wan I2V visual conditioning ──
dl_kijai "open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" \
         "models/clip_vision"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  MOTION CONTROL MODELS${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════${NC}"
echo ""

# ── VACE module 14B (for Wan Fun Control / VACE-based motion) (~6.1GB) ──
dl_kijai "Wan2_1-VACE_module_14B_bf16.safetensors" \
         "models/diffusion_models"

# ── VACE module 14B fp8 (lighter version ~3.1GB) ──
dl_kijai "Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors" \
         "models/diffusion_models"

# ── VACE module 1.3B (~1.5GB) ──
dl_kijai "Wan2_1-VACE_module_1_3B_bf16.safetensors" \
         "models/diffusion_models"

# ── CausVid Distilled T2V LoRA (fast 4-8 step generation) ──
dl_kijai "Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors" \
         "models/loras"

# ── AccVid T2V LoRA (accelerated generation) ──
dl_kijai "Wan21_AccVid_T2V_14B_lora_rank32_fp16.safetensors" \
         "models/loras"

# ── AccVid I2V LoRA ──
dl_kijai "Wan21_AccVid_I2V_480P_14B_lora_rank32_fp16.safetensors" \
         "models/loras"

# ================================================================
# STEP 5 — LORAS FROM CIVITAI
# ================================================================
if [ ${#LORAS[@]} -gt 0 ]; then
  if [ -z "$CIVITAI_API_KEY" ]; then
    err "CIVITAI_API_KEY is empty — skipping LoRAs. Add your key to the config above."
  else
    info "Downloading LoRAs..."
    for URL in "${LORAS[@]}"; do
      FULL_URL="${URL}&token=${CIVITAI_API_KEY}"
      FNAME=$(wget --server-response --spider "$FULL_URL" 2>&1 \
        | grep -i "content-disposition" \
        | sed -n 's/.*filename="\?\([^"]*\)"\?.*/\1/ip' | head -1 | tr -d '\r')
      [ -z "$FNAME" ] && FNAME="lora_$(echo "$URL" | grep -o 'models/[0-9]*' | tr '/' '_').safetensors"
      if [ ! -f "models/loras/$FNAME" ]; then
        info "Downloading: $FNAME"
        wget -q --show-progress "$FULL_URL" -O "models/loras/$FNAME" \
          && log "Saved: $FNAME" || err "Failed: $URL"
      else
        skip "LoRA $FNAME"
      fi
    done
  fi
else
  info "No LoRAs configured — skipping"
fi

# ================================================================
# STEP 6 — WRITE WORKFLOWS (using correct Kijai node types)
# ================================================================
info "Writing workflows to user/default/workflows/..."

# ── T2V WORKFLOW (Kijai WanVideoWrapper nodes) ───────────────────
cat > "user/default/workflows/WAN22_T2V.json" << 'EOF_T2V'
{
  "last_node_id": 9,
  "last_link_id": 7,
  "_comment": "Wan 2.1/2.2 T2V workflow using Kijai WanVideoWrapper. Uses pre-downloaded single-file models. Node: WanVideoModelLoader loads from models/diffusion_models/",
  "nodes": [
    {
      "id": 1,
      "type": "WanVideoModelLoader",
      "pos": [40, 80],
      "size": [320, 120],
      "outputs": [{"name": "model", "type": "WANMODEL", "links": [1], "slot_index": 0}],
      "widgets_values": ["Wan2_1-T2V-14B_fp8_e4m3fn.safetensors", "fp8_e4m3fn", "offload_device", true],
      "title": "Load Wan T2V 14B (fp8)"
    },
    {
      "id": 2,
      "type": "WanVideoVAELoader",
      "pos": [40, 240],
      "size": [320, 58],
      "outputs": [{"name": "vae", "type": "WANVAE", "links": [2], "slot_index": 0}],
      "widgets_values": ["Wan2_1_VAE_bf16.safetensors"],
      "title": "Load Wan VAE"
    },
    {
      "id": 3,
      "type": "WanVideoTextEncoderLoader",
      "pos": [40, 340],
      "size": [320, 58],
      "outputs": [{"name": "clip", "type": "CLIP", "links": [3], "slot_index": 0}],
      "widgets_values": ["umt5-xxl-enc-fp8_e4m3fn.safetensors"],
      "title": "Load UMT5 Text Encoder"
    },
    {
      "id": 4,
      "type": "WanVideoTextEncode",
      "pos": [420, 80],
      "size": [480, 200],
      "inputs": [{"name": "clip", "type": "CLIP", "link": 3, "slot_index": 0}],
      "outputs": [{"name": "conditioning", "type": "WANCOND", "links": [4], "slot_index": 0}],
      "widgets_values": [
        "A cinematic shot of a futuristic city at night, neon lights reflecting on wet streets, slow camera push forward, ultra detailed, 4K",
        "blurry, static, low quality, watermark, deformed",
        1.0
      ],
      "title": "Text Prompt"
    },
    {
      "id": 5,
      "type": "WanVideoLoraSelect",
      "pos": [40, 440],
      "size": [320, 82],
      "inputs":  [{"name": "model", "type": "WANMODEL", "link": null}],
      "outputs": [{"name": "model", "type": "WANMODEL", "links": []}],
      "widgets_values": ["None", 0.8],
      "title": "LoRA (optional)"
    },
    {
      "id": 6,
      "type": "WanVideoNoise",
      "pos": [420, 340],
      "size": [320, 100],
      "outputs": [{"name": "noise", "type": "NOISE", "links": [5], "slot_index": 0}],
      "widgets_values": [42, 81, 832, 480],
      "title": "Noise (81 frames, 832x480)"
    },
    {
      "id": 7,
      "type": "WanVideoSampler",
      "pos": [800, 160],
      "size": [360, 290],
      "inputs": [
        {"name": "model",        "type": "WANMODEL", "link": 1,  "slot_index": 0},
        {"name": "conditioning", "type": "WANCOND",  "link": 4,  "slot_index": 1},
        {"name": "noise",        "type": "NOISE",    "link": 5,  "slot_index": 2}
      ],
      "outputs": [{"name": "samples", "type": "LATENT", "links": [6], "slot_index": 0}],
      "widgets_values": [30, 5.0, "euler", "beta", 81, 832, 480, 1],
      "title": "WAN Sampler"
    },
    {
      "id": 8,
      "type": "WanVideoDecodeKeyframes",
      "pos": [1220, 160],
      "size": [320, 68],
      "inputs": [
        {"name": "samples", "type": "LATENT",  "link": 6, "slot_index": 0},
        {"name": "vae",     "type": "WANVAE",  "link": 2, "slot_index": 1}
      ],
      "outputs": [{"name": "images", "type": "IMAGE", "links": [7], "slot_index": 0}],
      "widgets_values": [true],
      "title": "VAE Decode"
    },
    {
      "id": 9,
      "type": "VHS_VideoCombine",
      "pos": [1600, 160],
      "size": [340, 200],
      "inputs": [{"name": "images", "type": "IMAGE", "link": 7, "slot_index": 0}],
      "widgets_values": [24, "wan_t2v_output", "video/h264-mp4", "Enabled", true, false, "ComfyUI", true, ""],
      "title": "Save Video (MP4)"
    }
  ],
  "links": [
    [1, 1, 0, 7, 0, "WANMODEL"],
    [2, 2, 0, 8, 1, "WANVAE"],
    [3, 3, 0, 4, 0, "CLIP"],
    [4, 4, 0, 7, 1, "WANCOND"],
    [5, 6, 0, 7, 2, "NOISE"],
    [6, 7, 0, 8, 0, "LATENT"],
    [7, 8, 0, 9, 0, "IMAGE"]
  ],
  "groups": [],
  "config": {},
  "extra": {"ds": {"scale": 1.0, "offset": [0, 0]}},
  "version": 0.4
}
EOF_T2V
log "WAN22_T2V.json written"

# ── I2V WORKFLOW (Kijai WanVideoWrapper nodes) ───────────────────
cat > "user/default/workflows/WAN22_I2V.json" << 'EOF_I2V'
{
  "last_node_id": 12,
  "last_link_id": 11,
  "_comment": "Wan 2.1/2.2 I2V workflow using Kijai WanVideoWrapper. Uses pre-downloaded single-file models from models/diffusion_models/. Upload a source image in LoadImage node.",
  "nodes": [
    {
      "id": 1,
      "type": "WanVideoModelLoader",
      "pos": [40, 60],
      "size": [320, 120],
      "outputs": [{"name": "model", "type": "WANMODEL", "links": [1], "slot_index": 0}],
      "widgets_values": ["Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors", "fp8_e4m3fn", "offload_device", true],
      "title": "Load Wan I2V 14B 480P (fp8)"
    },
    {
      "id": 2,
      "type": "WanVideoVAELoader",
      "pos": [40, 210],
      "size": [320, 58],
      "outputs": [{"name": "vae", "type": "WANVAE", "links": [2, 9], "slot_index": 0}],
      "widgets_values": ["Wan2_1_VAE_bf16.safetensors"],
      "title": "Load Wan VAE"
    },
    {
      "id": 3,
      "type": "WanVideoTextEncoderLoader",
      "pos": [40, 310],
      "size": [320, 58],
      "outputs": [{"name": "clip", "type": "CLIP", "links": [3], "slot_index": 0}],
      "widgets_values": ["umt5-xxl-enc-fp8_e4m3fn.safetensors"],
      "title": "Load UMT5 Text Encoder"
    },
    {
      "id": 4,
      "type": "CLIPVisionLoader",
      "pos": [40, 410],
      "size": [320, 58],
      "outputs": [{"name": "clip_vision", "type": "CLIP_VISION", "links": [8], "slot_index": 0}],
      "widgets_values": ["sigclip_vision_patch14_384.safetensors"],
      "title": "Load CLIP Vision"
    },
    {
      "id": 5,
      "type": "LoadImage",
      "pos": [40, 510],
      "size": [320, 340],
      "outputs": [
        {"name": "IMAGE", "type": "IMAGE", "links": [10], "slot_index": 0},
        {"name": "MASK",  "type": "MASK",  "links": [],   "slot_index": 1}
      ],
      "widgets_values": ["example.png", "image"],
      "title": "Source Image (Upload Here)"
    },
    {
      "id": 6,
      "type": "WanVideoTextEncode",
      "pos": [420, 60],
      "size": [480, 200],
      "inputs": [{"name": "clip", "type": "CLIP", "link": 3, "slot_index": 0}],
      "outputs": [{"name": "conditioning", "type": "WANCOND", "links": [4], "slot_index": 0}],
      "widgets_values": [
        "The subject moves naturally forward, cinematic smooth motion, high quality, photorealistic",
        "blurry, static, watermark, low quality, deformed",
        1.0
      ],
      "title": "Text Prompt"
    },
    {
      "id": 7,
      "type": "WanVideoLoraSelect",
      "pos": [40, 900],
      "size": [320, 82],
      "inputs":  [{"name": "model", "type": "WANMODEL", "link": null}],
      "outputs": [{"name": "model", "type": "WANMODEL", "links": []}],
      "widgets_values": ["None", 0.8],
      "title": "LoRA (optional)"
    },
    {
      "id": 8,
      "type": "WanVideoI2VEncode",
      "pos": [420, 320],
      "size": [420, 140],
      "inputs": [
        {"name": "clip_vision", "type": "CLIP_VISION", "link": 8,  "slot_index": 0},
        {"name": "image",       "type": "IMAGE",       "link": 10, "slot_index": 1},
        {"name": "vae",         "type": "WANVAE",      "link": 9,  "slot_index": 2}
      ],
      "outputs": [{"name": "conditioning", "type": "WANCOND", "links": [11], "slot_index": 0}],
      "widgets_values": [1.0],
      "title": "I2V Image Encode"
    },
    {
      "id": 9,
      "type": "WanVideoNoise",
      "pos": [900, 60],
      "size": [320, 100],
      "outputs": [{"name": "noise", "type": "NOISE", "links": [5], "slot_index": 0}],
      "widgets_values": [42, 81, 832, 480],
      "title": "Noise (81 frames, 832x480)"
    },
    {
      "id": 10,
      "type": "WanVideoSampler",
      "pos": [900, 220],
      "size": [380, 320],
      "inputs": [
        {"name": "model",              "type": "WANMODEL", "link": 1,  "slot_index": 0},
        {"name": "positive",           "type": "WANCOND",  "link": 4,  "slot_index": 1},
        {"name": "image_conditioning", "type": "WANCOND",  "link": 11, "slot_index": 2},
        {"name": "noise",              "type": "NOISE",    "link": 5,  "slot_index": 3}
      ],
      "outputs": [{"name": "samples", "type": "LATENT", "links": [6], "slot_index": 0}],
      "widgets_values": [30, 5.0, "euler", "beta", 81, 832, 480, 1],
      "title": "WAN Sampler"
    },
    {
      "id": 11,
      "type": "WanVideoDecodeKeyframes",
      "pos": [1340, 220],
      "size": [320, 68],
      "inputs": [
        {"name": "samples", "type": "LATENT", "link": 6, "slot_index": 0},
        {"name": "vae",     "type": "WANVAE", "link": 2, "slot_index": 1}
      ],
      "outputs": [{"name": "images", "type": "IMAGE", "links": [7], "slot_index": 0}],
      "widgets_values": [true],
      "title": "VAE Decode"
    },
    {
      "id": 12,
      "type": "VHS_VideoCombine",
      "pos": [1720, 220],
      "size": [340, 200],
      "inputs": [{"name": "images", "type": "IMAGE", "link": 7, "slot_index": 0}],
      "widgets_values": [24, "wan_i2v_output", "video/h264-mp4", "Enabled", true, false, "ComfyUI", true, ""],
      "title": "Save Video (MP4)"
    }
  ],
  "links": [
    [1,  1,  0, 10, 0, "WANMODEL"],
    [2,  2,  0, 11, 1, "WANVAE"],
    [3,  3,  0, 6,  0, "CLIP"],
    [4,  6,  0, 10, 1, "WANCOND"],
    [5,  9,  0, 10, 3, "NOISE"],
    [6,  10, 0, 11, 0, "LATENT"],
    [7,  11, 0, 12, 0, "IMAGE"],
    [8,  4,  0, 8,  0, "CLIP_VISION"],
    [9,  2,  0, 8,  2, "WANVAE"],
    [10, 5,  0, 8,  1, "IMAGE"],
    [11, 8,  0, 10, 2, "WANCOND"]
  ],
  "groups": [],
  "config": {},
  "extra": {"ds": {"scale": 1.0, "offset": [0, 0]}},
  "version": 0.4
}
EOF_I2V
log "WAN22_I2V.json written"

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}  ✅  WAN 2.2 SETUP COMPLETE${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo -e "  📦 Models downloaded to:   $COMFY/models/"
echo -e "  🎬 Workflows written to:   $COMFY/user/default/workflows/"
echo ""
echo -e "  Downloads: ${DL_PASSED} ok, ${DL_SKIPPED} skipped, ${DL_FAILED} failed (${DL_TOTAL} total)"
echo ""
echo -e "  Workflows:"
echo -e "    • WAN22_T2V.json  →  Text → Video (edit prompt in node 4)"
echo -e "    • WAN22_I2V.json  →  Image → Video (load image in node 5)"
echo ""
echo -e "  Model filenames (Kijai format):"
echo -e "    T2V:  Wan2_1-T2V-14B_fp8_e4m3fn.safetensors"
echo -e "    I2V:  Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors"
echo -e "    VAE:  Wan2_1_VAE_bf16.safetensors"
echo -e "    TE:   umt5-xxl-enc-fp8_e4m3fn.safetensors"
echo -e "    CLIP: sigclip_vision_patch14_384.safetensors"
echo ""
echo -e "  LoRA slot:"
echo -e "    Both workflows have a WanVideoLoraSelect node"
echo -e "    Set to 'None' by default — pick any .safetensors from models/loras/"
echo ""
echo -e "${CYAN}  Motion Control:"
echo -e "    VACE modules downloaded for Wan Fun Control workflows"
echo -e "    CausVid & AccVid LoRAs for fast generation"
echo -e "    ComfyUI-WanFunControlWrapper for reference video + controlnet${NC}"
echo ""
echo -e "${CYAN}  VRAM: 480p ≈ 18GB | 720p ≈ 28GB | A100/H100 recommended${NC}"
echo ""

if [ $DL_FAILED -gt 0 ]; then
  echo -e "${RED}  ⚠ $DL_FAILED downloads failed. Re-run this script to retry.${NC}"
  echo ""
fi
