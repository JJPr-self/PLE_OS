#!/bin/bash
###############################################################################
# PLEASUREDAI OS — Model Download Script (v2)
#
# Enhanced with:
#   - More model categories (ip-adapter, 3d, animatediff)
#   - Proper error logging to /var/log/nerv/model_download.log
#   - Download verification (file size check)
#   - Resume support via aria2c
#   - Progress reporting
#
# Usage:
#   ./get_models.sh --essential    # Core image models (~13GB)
#   ./get_models.sh --video        # Video generation models (~40GB+)
#   ./get_models.sh --face         # Face swap models (~3GB)
#   ./get_models.sh --loras        # Quality/style LoRAs (~2GB)
#   ./get_models.sh --controlnet   # ControlNet models (~5GB)
#   ./get_models.sh --animatediff  # AnimateDiff motion modules (~4GB)
#   ./get_models.sh --3d           # 3D generation models (~2GB)
#   ./get_models.sh --ipadapter    # IP-Adapter models (~6GB)
#   ./get_models.sh --all          # Everything
###############################################################################

set -o pipefail

MODELS_DIR="${MODELS_DIR:-/opt/comfyui/models}"
HF_TOKEN="${HF_TOKEN:-}"
MODE="${1:---essential}"
LOG_FILE="/var/log/nerv/model_download.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

mkdir -p "$(dirname "$LOG_FILE")"

# Counters
DL_TOTAL=0
DL_PASSED=0
DL_SKIPPED=0
DL_FAILED=0
DL_ERRORS=""

# ── Logging ──────────────────────────────────────────────────────────────────
dl_log() {
    local LEVEL="$1"
    shift
    local MSG="$*"
    local TS="$(date '+%H:%M:%S')"
    echo "[${TS}] [${LEVEL}] ${MSG}" | tee -a "$LOG_FILE"
}

# ── Download helper with verification ────────────────────────────────────────
download() {
    local URL="$1"
    local DEST="$2"
    local EXPECTED_SIZE="${3:-0}"  # Optional expected size in bytes for verification
    local NAME="$(basename "$DEST")"
    DL_TOTAL=$((DL_TOTAL + 1))

    if [ -f "$DEST" ]; then
        local ACTUAL_SIZE=$(stat -c%s "$DEST" 2>/dev/null || echo "0")
        # If expected size is set, verify file isn't truncated
        if [ "$EXPECTED_SIZE" -gt 0 ] && [ "$ACTUAL_SIZE" -lt "$EXPECTED_SIZE" ]; then
            dl_log "WARN" "${NAME}: File exists but appears truncated (${ACTUAL_SIZE} < ${EXPECTED_SIZE}). Re-downloading..."
            rm -f "$DEST"
        else
            dl_log "INFO" "✓ ${NAME} already exists ($(numfmt --to=iec $ACTUAL_SIZE 2>/dev/null || echo '?'))"
            DL_SKIPPED=$((DL_SKIPPED + 1))
            return 0
        fi
    fi

    mkdir -p "$(dirname "$DEST")"
    dl_log "INFO" "↓ Downloading ${NAME}..."

    # Build auth header for HuggingFace
    local AUTH_ARGS=""
    if [ -n "$HF_TOKEN" ] && [[ "$URL" == *"huggingface.co"* ]]; then
        AUTH_ARGS="--header=Authorization: Bearer ${HF_TOKEN}"
    fi

    local DL_RC=1
    if command -v aria2c &> /dev/null; then
        aria2c -x 8 -s 8 --max-tries=3 --retry-wait=5 \
            --console-log-level=warn \
            --download-result=hide \
            --summary-interval=10 \
            ${AUTH_ARGS} \
            -d "$(dirname "$DEST")" -o "$(basename "$DEST")" \
            "$URL" >> "$LOG_FILE" 2>&1
        DL_RC=$?
    else
        wget --progress=bar:force:noscroll -q --show-progress \
            ${AUTH_ARGS:+--header="Authorization: Bearer ${HF_TOKEN}"} \
            -O "$DEST" "$URL" 2>&1 | tee -a "$LOG_FILE"
        DL_RC=${PIPESTATUS[0]}
    fi

    if [ $DL_RC -ne 0 ]; then
        dl_log "ERROR" "✗ FAILED to download ${NAME}"
        DL_FAILED=$((DL_FAILED + 1))
        DL_ERRORS="${DL_ERRORS}\n  ✗ ${NAME}: download failed (exit ${DL_RC})"
        rm -f "$DEST"  # Remove partial file
        return 1
    fi

    # Verify file was actually created and isn't empty
    if [ ! -f "$DEST" ] || [ "$(stat -c%s "$DEST" 2>/dev/null || echo 0)" -lt 1000 ]; then
        dl_log "ERROR" "✗ ${NAME}: File missing or too small after download"
        DL_FAILED=$((DL_FAILED + 1))
        DL_ERRORS="${DL_ERRORS}\n  ✗ ${NAME}: file missing or empty"
        rm -f "$DEST"
        return 1
    fi

    local FINAL_SIZE=$(stat -c%s "$DEST" 2>/dev/null || echo "0")
    dl_log "INFO" "✓ ${NAME} downloaded ($(numfmt --to=iec $FINAL_SIZE 2>/dev/null || echo '?'))"
    DL_PASSED=$((DL_PASSED + 1))
    return 0
}

# ── HuggingFace shorthand ───────────────────────────────────────────────────
hf_download() {
    local REPO="$1"
    local FILE="$2"
    local DEST="$3"
    local SIZE="${4:-0}"
    download "https://huggingface.co/${REPO}/resolve/main/${FILE}" "$DEST" "$SIZE"
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║          PLEASUREDAI — Model Downloader v2.0            ║"
echo "╚══════════════════════════════════════════════════════════╝"
dl_log "INFO" "Mode: ${MODE}"
dl_log "INFO" "Target: ${MODELS_DIR}"
dl_log "INFO" "HF Token: $([ -n "$HF_TOKEN" ] && echo 'configured' || echo 'NOT SET (some models may fail)')"

###############################################################################
# ESSENTIAL (~13GB) — Minimum viable setup for image generation
###############################################################################
if [ "$MODE" = "--essential" ] || [ "$MODE" = "--all" ]; then
    echo ""
    dl_log "INFO" "═══ ESSENTIAL: Core Image Generation ═══"

    # SDXL Base 1.0 — The standard. Largest LoRA ecosystem, best documented.
    hf_download "stabilityai/stable-diffusion-xl-base-1.0" \
        "sd_xl_base_1.0.safetensors" \
        "${MODELS_DIR}/checkpoints/sd_xl_base_1.0.safetensors" \
        6938078334

    # SDXL VAE FP16 Fix — Prevents black images when using --fp16-vae flag
    hf_download "madebyollin/sdxl-vae-fp16-fix" \
        "sdxl_vae.safetensors" \
        "${MODELS_DIR}/vae/sdxl_vae_fp16fix.safetensors" \
        334641162

    # SDXL Refiner — Optional 2nd-pass detail enhancement
    hf_download "stabilityai/stable-diffusion-xl-refiner-1.0" \
        "sd_xl_refiner_1.0.safetensors" \
        "${MODELS_DIR}/checkpoints/sd_xl_refiner_1.0.safetensors" \
        6075981930

    # 4x-UltraSharp Upscaler — Best general-purpose 4x upscaler
    download "https://huggingface.co/Kim2091/UltraSharp/resolve/main/4x-UltraSharp.pth" \
        "${MODELS_DIR}/upscale_models/4x-UltraSharp.pth"

    # RealESRGAN x4plus — Alternative upscaler, good for anime/illustration
    download "https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x4.pth" \
        "${MODELS_DIR}/upscale_models/RealESRGAN_x4.pth"
fi

###############################################################################
# VIDEO MODELS (~50GB+) — WAN 2.1/2.2 (Kijai format), LTX, CogVideoX
# All URLs verified against actual HuggingFace repos. No huggingface-cli.
# Uses Kijai/WanVideo_comfy single-file format (what ComfyUI nodes expect).
###############################################################################
if [ "$MODE" = "--video" ] || [ "$MODE" = "--all" ]; then
    echo ""
    dl_log "INFO" "═══ VIDEO: Text-to-Video / Image-to-Video ═══"

    # ── Wan T2V 14B fp8 (~14.9GB) — Main text-to-video ──────────────────
    dl_log "INFO" "--- Wan T2V 14B (fp8, Kijai format) ---"
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-T2V-14B_fp8_e4m3fn.safetensors" \
        "${MODELS_DIR}/diffusion_models/Wan2_1-T2V-14B_fp8_e4m3fn.safetensors"

    # ── Wan T2V 1.3B fp8 (~1.5GB) — Lightweight ─────────────────────────
    dl_log "INFO" "--- Wan T2V 1.3B (fp8, Kijai format) ---"
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-T2V-1_3B_fp8_e4m3fn.safetensors" \
        "${MODELS_DIR}/diffusion_models/Wan2_1-T2V-1_3B_fp8_e4m3fn.safetensors"

    # ── Wan I2V 480P 14B fp8 (~17GB) — Image-to-video ───────────────────
    dl_log "INFO" "--- Wan I2V 480P 14B (fp8, Kijai format) ---"
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors" \
        "${MODELS_DIR}/diffusion_models/Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors"

    # ── Wan I2V 720P 14B fp8 (~17GB) ─────────────────────────────────────
    dl_log "INFO" "--- Wan I2V 720P 14B (fp8, Kijai format) ---"
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors" \
        "${MODELS_DIR}/diffusion_models/Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors"

    # ── Wan 2.2 I2V A14B HIGH (~28.6GB) — Enhanced Wan 2.2 ──────────────
    dl_log "INFO" "--- Wan 2.2 I2V A14B HIGH (bf16) ---"
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_2-I2V-A14B-HIGH_bf16.safetensors" \
        "${MODELS_DIR}/diffusion_models/Wan2_2-I2V-A14B-HIGH_bf16.safetensors"

    # ── VAE (Wan 2.1 ~254MB + Wan 2.2 ~1.4GB) ───────────────────────────
    dl_log "INFO" "--- Wan VAE ---"
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors" \
        "${MODELS_DIR}/vae/Wan2_1_VAE_bf16.safetensors"

    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_2_VAE_bf16.safetensors" \
        "${MODELS_DIR}/vae/Wan2_2_VAE_bf16.safetensors"

    # ── UMT5-XXL Text Encoder fp8 (~6.7GB, Kijai format) ────────────────
    dl_log "INFO" "--- UMT5-XXL Text Encoder ---"
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/umt5-xxl-enc-fp8_e4m3fn.safetensors" \
        "${MODELS_DIR}/text_encoders/umt5-xxl-enc-fp8_e4m3fn.safetensors"

    # ── CLIP Vision for I2V (~856MB) ─────────────────────────────────────
    dl_log "INFO" "--- SigCLIP Vision 384 ---"
    download "https://huggingface.co/Comfy-Org/sigclip_vision_384/resolve/main/sigclip_vision_patch14_384.safetensors" \
        "${MODELS_DIR}/clip_vision/sigclip_vision_patch14_384.safetensors"

    # ── Open-CLIP Visual (~1.3GB) — For Wan I2V visual conditioning ──────
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors" \
        "${MODELS_DIR}/clip_vision/open-clip-xlm-roberta-large-vit-huge-14_visual_fp16.safetensors"

    # ── VACE module 14B fp8 (~3.1GB) — Motion control ────────────────────
    dl_log "INFO" "--- VACE Motion Control ---"
    download "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors" \
        "${MODELS_DIR}/diffusion_models/Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors"

    # ── Comfy-Org Native T2V 14B fp8 (~14.3GB) — Alternative format ─────
    dl_log "INFO" "--- Comfy-Org Native Models (alternative) ---"
    download "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_14B_fp8_e4m3fn.safetensors" \
        "${MODELS_DIR}/diffusion_models/wan2.1_t2v_14B_fp8_e4m3fn.safetensors"

    # ── Comfy-Org Native UMT5 fp8 scaled (~6.7GB) ───────────────────────
    download "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
        "${MODELS_DIR}/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

    # ── Comfy-Org Native VAE (~254MB) ────────────────────────────────────
    download "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
        "${MODELS_DIR}/vae/wan_2.1_vae.safetensors"

    # ── LTX Video ─────────────────────────────────────────────────────────
    # Lightweight, fast. Great for RTX 3090. Good quality/speed tradeoff.
    dl_log "INFO" "--- LTX Video 2B ---"
    hf_download "Lightricks/LTX-Video" \
        "ltx-video-2b-v0.9.1.safetensors" \
        "${MODELS_DIR}/checkpoints/ltx-video-2b-v0.9.1.safetensors"

    # ── CogVideoX-5B ─────────────────────────────────────────────────────
    # Tencent's strong T2V. Good motion quality, diverse outputs.
    dl_log "INFO" "--- CogVideoX 5B ---"
    hf_download "THUDM/CogVideoX-5b" \
        "transformer/diffusion_pytorch_model.safetensors" \
        "${MODELS_DIR}/diffusion_models/cogvideox_5b_transformer.safetensors"

    hf_download "THUDM/CogVideoX-5b" \
        "vae/diffusion_pytorch_model.safetensors" \
        "${MODELS_DIR}/vae/cogvideox_5b_vae.safetensors"
fi

###############################################################################
# FACE SWAP / IDENTITY (~3GB)
###############################################################################
if [ "$MODE" = "--face" ] || [ "$MODE" = "--all" ]; then
    echo ""
    dl_log "INFO" "═══ FACE: Swap & Restoration ═══"

    # InsightFace buffalo_l detection pack (all 5 ONNX files)
    INSIGHT_DIR="${MODELS_DIR}/insightface/models/buffalo_l"
    mkdir -p "$INSIGHT_DIR"
    for ONNX_FILE in 1k3d68.onnx 2d106det.onnx det_10g.onnx genderage.onnx w600k_r50.onnx; do
        download "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/buffalo_l/${ONNX_FILE}" \
            "${INSIGHT_DIR}/${ONNX_FILE}"
    done

    # InSwapper 128 — Core face swap model
    download "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx" \
        "${MODELS_DIR}/insightface/inswapper_128.onnx"

    # CodeFormer v0.1.0 — Best face restoration (fixes swap artifacts)
    download "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/codeformer-v0.1.0.pth" \
        "${MODELS_DIR}/facerestore_models/codeformer-v0.1.0.pth"

    # GFPGAN v1.4 — Alternative face restoration
    download "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GFPGANv1.4.pth" \
        "${MODELS_DIR}/facerestore_models/GFPGANv1.4.pth"
fi

###############################################################################
# IP-ADAPTER (~6GB) — Face/style consistency via image prompting
###############################################################################
if [ "$MODE" = "--ipadapter" ] || [ "$MODE" = "--all" ]; then
    echo ""
    dl_log "INFO" "═══ IP-ADAPTER: Image Prompting ═══"

    # IP-Adapter Plus SDXL
    hf_download "h94/IP-Adapter" \
        "sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors" \
        "${MODELS_DIR}/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors"

    # IP-Adapter FaceID Plus V2 SDXL
    hf_download "h94/IP-Adapter-FaceID" \
        "ip-adapter-faceid-plusv2_sdxl.bin" \
        "${MODELS_DIR}/ipadapter/ip-adapter-faceid-plusv2_sdxl.bin"

    # CLIP Vision model (required by IP-Adapter)
    hf_download "h94/IP-Adapter" \
        "models/image_encoder/model.safetensors" \
        "${MODELS_DIR}/clip_vision/ip_adapter_clip_vit_h.safetensors"

    # IP-Adapter Plus SD1.5 (smaller, faster)
    hf_download "h94/IP-Adapter" \
        "models/ip-adapter-plus_sd15.safetensors" \
        "${MODELS_DIR}/ipadapter/ip-adapter-plus_sd15.safetensors"
fi

###############################################################################
# LORAS (~2GB) — Quality and style enhancers
###############################################################################
if [ "$MODE" = "--loras" ] || [ "$MODE" = "--all" ]; then
    echo ""
    dl_log "INFO" "═══ LoRA: Style & Quality ═══"

    # SDXL Offset LoRA — Official Stability AI, dramatic lighting
    hf_download "stabilityai/stable-diffusion-xl-base-1.0" \
        "sd_xl_offset_example-lora_1.0.safetensors" \
        "${MODELS_DIR}/loras/sd_xl_offset_lora.safetensors"

    # SDXL Lightning LoRA (4-step) — Ultra-fast generation
    hf_download "ByteDance/SDXL-Lightning" \
        "sdxl_lightning_4step_lora.safetensors" \
        "${MODELS_DIR}/loras/sdxl_lightning_4step_lora.safetensors"

    # SDXL Turbo LoRA — Single-step generation
    hf_download "ByteDance/SDXL-Lightning" \
        "sdxl_lightning_1step_lora.safetensors" \
        "${MODELS_DIR}/loras/sdxl_lightning_1step_lora.safetensors"

    # LCM LoRA SDXL — Latent Consistency Model, 4-8 steps
    hf_download "latent-consistency/lcm-lora-sdxl" \
        "pytorch_lora_weights.safetensors" \
        "${MODELS_DIR}/loras/lcm_lora_sdxl.safetensors"
fi

###############################################################################
# CONTROLNET (~5GB) — Structural guidance
###############################################################################
if [ "$MODE" = "--controlnet" ] || [ "$MODE" = "--all" ]; then
    echo ""
    dl_log "INFO" "═══ CONTROLNET: Structural Guidance ═══"

    # Depth (SDXL)
    hf_download "diffusers/controlnet-depth-sdxl-1.0" \
        "diffusion_pytorch_model.fp16.safetensors" \
        "${MODELS_DIR}/controlnet/controlnet_depth_sdxl_fp16.safetensors"

    # Canny (SDXL)
    hf_download "diffusers/controlnet-canny-sdxl-1.0" \
        "diffusion_pytorch_model.fp16.safetensors" \
        "${MODELS_DIR}/controlnet/controlnet_canny_sdxl_fp16.safetensors"

    # OpenPose (SDXL) — Thibaud
    hf_download "thibaud/controlnet-openpose-sdxl-1.0" \
        "OpenPoseXL2.safetensors" \
        "${MODELS_DIR}/controlnet/controlnet_openpose_sdxl.safetensors"
fi

###############################################################################
# ANIMATEDIFF (~4GB) — Motion modules for animation
###############################################################################
if [ "$MODE" = "--animatediff" ] || [ "$MODE" = "--all" ]; then
    echo ""
    dl_log "INFO" "═══ ANIMATEDIFF: Motion Modules ═══"

    # AnimateDiff v3 Motion Module (SD 1.5)
    hf_download "guoyww/animatediff" \
        "v3_sd15_mm.ckpt" \
        "${MODELS_DIR}/animatediff_models/v3_sd15_mm.ckpt"

    # AnimateDiff SDXL Beta
    hf_download "guoyww/animatediff" \
        "mm_sdxl_v10_beta.ckpt" \
        "${MODELS_DIR}/animatediff_models/mm_sdxl_v10_beta.ckpt"

    # AnimateDiff Motion LoRA — Zoom In
    hf_download "guoyww/animatediff-motion-lora-v2" \
        "v2_lora_ZoomIn.ckpt" \
        "${MODELS_DIR}/animatediff_motion_lora/v2_lora_ZoomIn.ckpt"

    # AnimateDiff Motion LoRA — Pan Left
    hf_download "guoyww/animatediff-motion-lora-v2" \
        "v2_lora_PanLeft.ckpt" \
        "${MODELS_DIR}/animatediff_motion_lora/v2_lora_PanLeft.ckpt"
fi

###############################################################################
# 3D GENERATION (~2GB)
###############################################################################
if [ "$MODE" = "--3d" ] || [ "$MODE" = "--all" ]; then
    echo ""
    dl_log "INFO" "═══ 3D: Depth & Mesh Generation ═══"

    # Marigold depth estimation (v1)
    hf_download "prs-eth/marigold-lcm-v1-0" \
        "diffusion_pytorch_model.safetensors" \
        "${MODELS_DIR}/checkpoints/marigold_lcm_v1.safetensors" 2>/dev/null || \
        dl_log "WARN" "Marigold model download failed — can be installed via ComfyUI Manager"
fi

###############################################################################
# SUMMARY
###############################################################################
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Download Summary                                       ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Total:    ${DL_TOTAL}"
echo "║  Success:  ${DL_PASSED}"
echo "║  Skipped:  ${DL_SKIPPED} (already present)"
echo "║  Failed:   ${DL_FAILED}"

if [ $DL_FAILED -gt 0 ]; then
    echo "║"
    echo "║  Failed downloads:"
    echo -e "${DL_ERRORS}"
fi

TOTAL_SIZE=$(du -sh "${MODELS_DIR}" 2>/dev/null | cut -f1)
echo "║"
echo "║  Total model size: ${TOTAL_SIZE}"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
dl_log "INFO" "Download session complete: ${DL_PASSED} ok, ${DL_SKIPPED} skipped, ${DL_FAILED} failed"

exit $DL_FAILED
