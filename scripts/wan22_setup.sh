#!/bin/bash
# ================================================================
#  WAN 2.2 14B — MODELS + WORKFLOWS ONLY
#  For Vast.ai ComfyUI template (ComfyUI already running)
#  Skips anything already present. Zero input needed.
#  T2V + I2V | LoRA-ready | Custom workflows injected
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
if   [ -d "/workspace/ComfyUI" ];  then COMFY="/workspace/ComfyUI"
elif [ -d "/ComfyUI" ];            then COMFY="/ComfyUI"
elif [ -d "/opt/comfyui" ];        then COMFY="/opt/comfyui"
elif [ -d "$HOME/ComfyUI" ];       then COMFY="$HOME/ComfyUI"
else err "ComfyUI not found. Check your instance." && exit 1
fi
info "ComfyUI detected at: $COMFY"
cd "$COMFY"

# ================================================================
# STEP 1 — HF LOGIN + FAST TRANSFER
# ================================================================
pip install -q hf_transfer huggingface_hub 2>/dev/null
export HF_HUB_ENABLE_HF_TRANSFER=1

if [ -n "$HF_TOKEN" ]; then
  huggingface-cli login --token "$HF_TOKEN" --add-to-git-credential 2>/dev/null || true
  log "HuggingFace login OK"
fi

# ================================================================
# STEP 2 — CUSTOM NODES (skip if already installed)
# ================================================================
info "Checking custom nodes..."
cd "$COMFY/custom_nodes"

install_node() {
  local dir="$1" url="$2"
  if [ ! -d "$dir" ]; then
    info "Installing $dir..."
    git clone -q "$url" "$dir"
    if [ -f "$dir/requirements.txt" ]; then
      pip install -q -r "$dir/requirements.txt" 2>/dev/null || true
    fi
    log "$dir installed"
  else
    skip "$dir"
  fi
}

install_node "ComfyUI-WanVideoWrapper"  "https://github.com/kijai/ComfyUI-WanVideoWrapper"
install_node "ComfyUI-VideoHelperSuite" "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
install_node "ComfyUI-GGUF"             "https://github.com/city96/ComfyUI-GGUF"

cd "$COMFY"

# ================================================================
# STEP 3 — DIRECTORIES
# ================================================================
mkdir -p models/diffusion_models \
         models/vae \
         models/text_encoders \
         models/clip_vision \
         models/loras \
         user/default/workflows
log "Directories OK"

# ================================================================
# STEP 4 — MODELS (skip if file exists)
# ================================================================
dl_hf() {
  local repo="$1" file="$2" dest="$3"
  if [ ! -f "$dest/$file" ]; then
    info "Downloading $file ..."
    huggingface-cli download "$repo" "$file" --local-dir "$dest"
    log "$file done"
  else
    skip "$file"
  fi
}

# T2V 14B fp8 (~14GB)
dl_hf "Kijai/WanVideo-fp8" \
      "wan2.2_t2v_14B_fp8_e4m3fn.safetensors" \
      "models/diffusion_models"

# I2V 480P 14B fp8 (~14GB)
dl_hf "Kijai/WanVideo-fp8" \
      "wan2.2_i2v_480p_14B_fp8_e4m3fn.safetensors" \
      "models/diffusion_models"

# VAE (~500MB)
dl_hf "Wan-AI/Wan2.2-T2V-14B" \
      "Wan_2.2_VAE.safetensors" \
      "models/vae"

# Text encoder GGUF (~5GB)
dl_hf "city96/umt5-xxl-enc-gguf" \
      "umt5-xxl-encoder-Q8_0.gguf" \
      "models/text_encoders"

# CLIP Vision for I2V (~900MB)
dl_hf "Comfy-Org/sigclip_vision_384" \
      "sigclip_vision_patch14_384.safetensors" \
      "models/clip_vision"

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
# STEP 6 — WRITE WORKFLOWS
# ================================================================
info "Writing workflows to user/default/workflows/..."

# ── T2V WORKFLOW ─────────────────────────────────────────────────
cat > "user/default/workflows/WAN22_T2V.json" << 'EOF_T2V'
{
  "last_node_id": 9,
  "last_link_id": 7,
  "nodes": [
    {
      "id": 1,
      "type": "WanVideoModelLoader",
      "pos": [40, 80],
      "size": [320, 98],
      "outputs": [{"name": "model", "type": "WANVIDEOMODEL", "links": [1], "slot_index": 0}],
      "widgets_values": ["wan2.2_t2v_14B_fp8_e4m3fn.safetensors", "fp8_e4m3fn", "offload_device", true]
    },
    {
      "id": 2,
      "type": "WanVideoVAELoader",
      "pos": [40, 220],
      "size": [320, 58],
      "outputs": [{"name": "vae", "type": "WANVIDEOVAE", "links": [2], "slot_index": 0}],
      "widgets_values": ["Wan_2.2_VAE.safetensors"]
    },
    {
      "id": 3,
      "type": "UMT5TextEncoderLoader",
      "pos": [40, 310],
      "size": [320, 58],
      "outputs": [{"name": "clip", "type": "CLIP", "links": [3], "slot_index": 0}],
      "widgets_values": ["umt5-xxl-encoder-Q8_0.gguf"]
    },
    {
      "id": 4,
      "type": "WanVideoTextEncode",
      "pos": [420, 80],
      "size": [480, 200],
      "inputs": [{"name": "clip", "type": "CLIP", "link": 3, "slot_index": 0}],
      "outputs": [{"name": "conditioning", "type": "WANCOND", "links": [4], "slot_index": 0}],
      "widgets_values": [
        "A cinematic shot of a futuristic city at night, neon lights reflecting on wet streets, slow camera push forward, ultra detailed",
        "blurry, static, low quality, watermark",
        1.0
      ]
    },
    {
      "id": 5,
      "type": "WanVideoLoraSelect",
      "pos": [40, 400],
      "size": [320, 82],
      "inputs":  [{"name": "model", "type": "WANVIDEOMODEL", "link": null}],
      "outputs": [{"name": "model", "type": "WANVIDEOMODEL", "links": []}],
      "widgets_values": ["None", 0.8]
    },
    {
      "id": 6,
      "type": "WanVideoNoise",
      "pos": [420, 340],
      "size": [320, 100],
      "outputs": [{"name": "noise", "type": "NOISE", "links": [5], "slot_index": 0}],
      "widgets_values": [42, 81, 512, 512]
    },
    {
      "id": 7,
      "type": "WanVideoSampler",
      "pos": [800, 160],
      "size": [360, 290],
      "inputs": [
        {"name": "model",        "type": "WANVIDEOMODEL", "link": 1,  "slot_index": 0},
        {"name": "conditioning", "type": "WANCOND",       "link": 4,  "slot_index": 1},
        {"name": "noise",        "type": "NOISE",         "link": 5,  "slot_index": 2}
      ],
      "outputs": [{"name": "samples", "type": "LATENT", "links": [6], "slot_index": 0}],
      "widgets_values": [30, 5.0, "euler", "beta", 81, 512, 512, 1]
    },
    {
      "id": 8,
      "type": "WanVideoDecodeKeyframes",
      "pos": [1220, 160],
      "size": [320, 68],
      "inputs": [
        {"name": "samples", "type": "LATENT",      "link": 6, "slot_index": 0},
        {"name": "vae",     "type": "WANVIDEOVAE", "link": 2, "slot_index": 1}
      ],
      "outputs": [{"name": "images", "type": "IMAGE", "links": [7], "slot_index": 0}],
      "widgets_values": [true]
    },
    {
      "id": 9,
      "type": "VHS_VideoCombine",
      "pos": [1600, 160],
      "size": [340, 200],
      "inputs": [{"name": "images", "type": "IMAGE", "link": 7, "slot_index": 0}],
      "widgets_values": [24, "wan22_t2v", "video/h264-mp4", "Enabled", true, false, "ComfyUI", true, ""]
    }
  ],
  "links": [
    [1, 1, 0, 7, 0, "WANVIDEOMODEL"],
    [2, 2, 0, 8, 1, "WANVIDEOVAE"],
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

# ── I2V WORKFLOW ─────────────────────────────────────────────────
cat > "user/default/workflows/WAN22_I2V.json" << 'EOF_I2V'
{
  "last_node_id": 12,
  "last_link_id": 11,
  "nodes": [
    {
      "id": 1,
      "type": "WanVideoModelLoader",
      "pos": [40, 60],
      "size": [320, 98],
      "outputs": [{"name": "model", "type": "WANVIDEOMODEL", "links": [1], "slot_index": 0}],
      "widgets_values": ["wan2.2_i2v_480p_14B_fp8_e4m3fn.safetensors", "fp8_e4m3fn", "offload_device", true]
    },
    {
      "id": 2,
      "type": "WanVideoVAELoader",
      "pos": [40, 190],
      "size": [320, 58],
      "outputs": [{"name": "vae", "type": "WANVIDEOVAE", "links": [2, 9], "slot_index": 0}],
      "widgets_values": ["Wan_2.2_VAE.safetensors"]
    },
    {
      "id": 3,
      "type": "UMT5TextEncoderLoader",
      "pos": [40, 280],
      "size": [320, 58],
      "outputs": [{"name": "clip", "type": "CLIP", "links": [3], "slot_index": 0}],
      "widgets_values": ["umt5-xxl-encoder-Q8_0.gguf"]
    },
    {
      "id": 4,
      "type": "CLIPVisionLoader",
      "pos": [40, 370],
      "size": [320, 58],
      "outputs": [{"name": "clip_vision", "type": "CLIP_VISION", "links": [8], "slot_index": 0}],
      "widgets_values": ["sigclip_vision_patch14_384.safetensors"]
    },
    {
      "id": 5,
      "type": "LoadImage",
      "pos": [40, 460],
      "size": [320, 340],
      "outputs": [
        {"name": "IMAGE", "type": "IMAGE", "links": [10], "slot_index": 0},
        {"name": "MASK",  "type": "MASK",  "links": [],   "slot_index": 1}
      ],
      "widgets_values": ["example.png", "image"]
    },
    {
      "id": 6,
      "type": "WanVideoTextEncode",
      "pos": [420, 60],
      "size": [480, 200],
      "inputs": [{"name": "clip", "type": "CLIP", "link": 3, "slot_index": 0}],
      "outputs": [{"name": "conditioning", "type": "WANCOND", "links": [4], "slot_index": 0}],
      "widgets_values": [
        "The subject moves naturally forward, cinematic smooth motion, high quality",
        "blurry, static, watermark, low quality",
        1.0
      ]
    },
    {
      "id": 7,
      "type": "WanVideoLoraSelect",
      "pos": [40, 840],
      "size": [320, 82],
      "inputs":  [{"name": "model", "type": "WANVIDEOMODEL", "link": null}],
      "outputs": [{"name": "model", "type": "WANVIDEOMODEL", "links": []}],
      "widgets_values": ["None", 0.8]
    },
    {
      "id": 8,
      "type": "WanVideoI2VEncode",
      "pos": [420, 320],
      "size": [420, 140],
      "inputs": [
        {"name": "clip_vision", "type": "CLIP_VISION", "link": 8,  "slot_index": 0},
        {"name": "image",       "type": "IMAGE",       "link": 10, "slot_index": 1},
        {"name": "vae",         "type": "WANVIDEOVAE", "link": 9,  "slot_index": 2}
      ],
      "outputs": [{"name": "conditioning", "type": "WANCOND", "links": [11], "slot_index": 0}],
      "widgets_values": [1.0]
    },
    {
      "id": 9,
      "type": "WanVideoNoise",
      "pos": [900, 60],
      "size": [320, 100],
      "outputs": [{"name": "noise", "type": "NOISE", "links": [5], "slot_index": 0}],
      "widgets_values": [42, 81, 480, 832]
    },
    {
      "id": 10,
      "type": "WanVideoSampler",
      "pos": [900, 220],
      "size": [380, 320],
      "inputs": [
        {"name": "model",              "type": "WANVIDEOMODEL", "link": 1,  "slot_index": 0},
        {"name": "positive",           "type": "WANCOND",       "link": 4,  "slot_index": 1},
        {"name": "image_conditioning", "type": "WANCOND",       "link": 11, "slot_index": 2},
        {"name": "noise",              "type": "NOISE",         "link": 5,  "slot_index": 3}
      ],
      "outputs": [{"name": "samples", "type": "LATENT", "links": [6], "slot_index": 0}],
      "widgets_values": [30, 5.0, "euler", "beta", 81, 480, 832, 1]
    },
    {
      "id": 11,
      "type": "WanVideoDecodeKeyframes",
      "pos": [1340, 220],
      "size": [320, 68],
      "inputs": [
        {"name": "samples", "type": "LATENT",      "link": 6, "slot_index": 0},
        {"name": "vae",     "type": "WANVIDEOVAE", "link": 2, "slot_index": 1}
      ],
      "outputs": [{"name": "images", "type": "IMAGE", "links": [7], "slot_index": 0}],
      "widgets_values": [true]
    },
    {
      "id": 12,
      "type": "VHS_VideoCombine",
      "pos": [1720, 220],
      "size": [340, 200],
      "inputs": [{"name": "images", "type": "IMAGE", "link": 7, "slot_index": 0}],
      "widgets_values": [24, "wan22_i2v", "video/h264-mp4", "Enabled", true, false, "ComfyUI", true, ""]
    }
  ],
  "links": [
    [1,  1,  0, 10, 0, "WANVIDEOMODEL"],
    [2,  2,  0, 11, 1, "WANVIDEOVAE"],
    [3,  3,  0, 6,  0, "CLIP"],
    [4,  6,  0, 10, 1, "WANCOND"],
    [5,  9,  0, 10, 3, "NOISE"],
    [6,  10, 0, 11, 0, "LATENT"],
    [7,  11, 0, 12, 0, "IMAGE"],
    [8,  4,  0, 8,  0, "CLIP_VISION"],
    [9,  2,  0, 8,  2, "WANVIDEOVAE"],
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
echo -e "  Workflows:"
echo -e "    • WAN22_T2V.json  →  Text → Video (edit prompt in node 4)"
echo -e "    • WAN22_I2V.json  →  Image → Video (load image in node 5)"
echo ""
echo -e "  LoRA slot:"
echo -e "    Both workflows have a WanVideoLoraSelect node (node 5 / node 7)"
echo -e "    Set to 'None' by default — pick any .safetensors from models/loras/"
echo ""
echo -e "${CYAN}  VRAM: 480p ≈ 18GB | 720p ≈ 28GB | A100/H100 recommended${NC}"
echo -e "${CYAN}  OOM?  Add --fp8_e4m3fn_unet to your ComfyUI launch args${NC}"
echo ""
