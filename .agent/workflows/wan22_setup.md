---
description: Download Models and Configure Wan2.2 Workflows Interactive Setup
---

Run the interactive node and model downloading setup script to configure ComfyUI for Wan2.2 workflows. Downloads all required models (diffusion models, VAE, text encoder, CLIP vision, VACE motion control modules) using verified direct download URLs.

**IMPORTANT**: This script uses `wget`/`aria2c` for ALL downloads — NO huggingface-cli. All model URLs are verified against the actual HuggingFace repos.

This requires the `pleasured_ai` docker container to be running and a terminal attached.

## Prerequisites

- HuggingFace Token (for gated models)
- CivitAI API Key (optional, for LoRAs)

## Steps

1. First, make sure your HuggingFace Token and CivitAI API Key are ready.
2. Run the interactive setup script inside the container:

```bash
cd "/opt/scripts"
chmod +x wan22_setup.sh
bash wan22_setup.sh
```

3. Follow the prompts to enter API keys (or press Enter to skip).

## What Gets Installed

### Custom Nodes

- `ComfyUI-WanVideoWrapper` — Core Wan video generation
- `ComfyUI-VideoHelperSuite` — Video encoding/saving
- `ComfyUI-GGUF` — GGUF model support
- `ComfyUI-KJNodes` — Utility nodes
- `ComfyUI_Controlnet_aux` — Pose/depth/canny preprocessors
- `ComfyUI-Advanced-ControlNet` — Advanced ControlNet
- `ComfyUI-AnimateDiff-Evolved` — AnimateDiff
- `ComfyUI_IPAdapter_plus` — Face/style consistency
- `ComfyUI-WanFunControlWrapper` — Motion control (reference video)
- `ComfyUI-UniRig` — 3D rigging / pose estimation
- `comfyui-reactor-node` — Face swap

### Models (from Kijai/WanVideo_comfy)

| Model        | Filename                                        | Size    |
| ------------ | ----------------------------------------------- | ------- |
| T2V 14B fp8  | `Wan2_1-T2V-14B_fp8_e4m3fn.safetensors`         | ~15GB   |
| T2V 1.3B fp8 | `Wan2_1-T2V-1_3B_fp8_e4m3fn.safetensors`        | ~1.5GB  |
| I2V 480P fp8 | `Wan2_1-I2V-14B-480P_fp8_e4m3fn.safetensors`    | ~17GB   |
| I2V 720P fp8 | `Wan2_1-I2V-14B-720P_fp8_e4m3fn.safetensors`    | ~17GB   |
| Wan 2.2 I2V  | `Wan2_2-I2V-A14B-HIGH_bf16.safetensors`         | ~28.6GB |
| VAE 2.1      | `Wan2_1_VAE_bf16.safetensors`                   | ~254MB  |
| VAE 2.2      | `Wan2_2_VAE_bf16.safetensors`                   | ~1.4GB  |
| Text Encoder | `umt5-xxl-enc-fp8_e4m3fn.safetensors`           | ~6.7GB  |
| CLIP Vision  | `sigclip_vision_patch14_384.safetensors`        | ~856MB  |
| VACE 14B fp8 | `Wan2_1-VACE_module_14B_fp8_e4m3fn.safetensors` | ~3.1GB  |

### Workflows

- `WAN22_T2V.json` → Text-to-Video (edit prompt in text node)
- `WAN22_I2V.json` → Image-to-Video (upload image in LoadImage node)
