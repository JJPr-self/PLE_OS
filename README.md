# PLEASUREDAI OS — NERV GENESIS

> **AI Video/Image/Audio Generation Suite powered by ComfyUI**  
> Evangelion-themed command center for RTX 3090/4090 GPUs on vast.ai

![NERV Genesis](https://img.shields.io/badge/NERV-GENESIS-e91e8c?style=for-the-badge&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMDAgMTAwIj48dGV4dCB5PSIuOWVtIiBmb250LXNpemU9IjkwIj7wn5SSPC90ZXh0Pjwvc3ZnPg==)
![CUDA](https://img.shields.io/badge/CUDA-12.1.1-76B900?style=for-the-badge&logo=nvidia)
![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=for-the-badge&logo=docker)
![vast.ai](https://img.shields.io/badge/vast.ai-Optimized-6b3fa0?style=for-the-badge)

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Building the Image](#building-the-image)
- [Deploying on vast.ai](#deploying-on-vastai)
- [Deploying on Other Cloud Hosts](#deploying-on-other-cloud-hosts)
- [Model Downloads](#model-downloads)
- [Using ComfyUI](#using-comfyui)
- [Workflow Guides](#workflow-guides)
- [Face Swap & Deepfake Workflows](#face-swap--deepfake-workflows)
- [Real-Time Webcam](#real-time-webcam)
- [GPU Optimization Guide](#gpu-optimization-guide)
- [Security](#security)
- [Pushing to Container Registry](#pushing-to-container-registry)
- [Troubleshooting](#troubleshooting)
- [Recommended Models](#recommended-models)

---

## Overview

PLEASUREDAI OS / NERV Genesis is a production-ready Docker deployment of ComfyUI with:

- **30+ pre-installed custom nodes** for video, face swap, audio, and image generation
- **NERV-themed web dashboard** with real-time GPU monitoring and simplified generation
- **Top open-source models** support: WAN 2.2, LTX Video, CogVideoX, SDXL
- **One-click deployment** to vast.ai with automatic startup
- **Authentication** to secure cloud deployments

---

## Features

| Category  | Capabilities                                                             |
| --------- | ------------------------------------------------------------------------ |
| **Image** | SDXL text-to-image, ControlNet, IP-Adapter, upscaling (4x UltraSharp)    |
| **Video** | WAN 2.2 (14B), LTX Video, CogVideoX-5B, AnimateDiff, frame interpolation |
| **Face**  | ReActor face swap, InstantID, IP-Adapter FaceID, CodeFormer restoration  |
| **Audio** | TTS synthesis, audio muxing with video, voice generation                 |
| **Tools** | LoRA/embedding support, batch processing, tiled VAE, webcam capture      |

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Docker Container                    │
│  ┌──────────────┐  ┌────────────┐  ┌──────────────┐│
│  │  Nginx :80   │──│ NERV UI    │  │ ComfyUI      ││
│  │ Reverse Proxy│  │ :3000      │  │ :8188        ││
│  └──────┬───────┘  └────────────┘  └──────┬───────┘│
│         │                                  │        │
│  ┌──────┴──────────────────────────────────┴──────┐ │
│  │              Models Volume                      │ │
│  │  checkpoints/ vae/ loras/ diffusion_models/    │ │
│  │  insightface/ facerestore_models/ embeddings/  │ │
│  └────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────┐ │
│  │     CUDA 12.1.1 + PyTorch + xFormers          │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- Docker with NVIDIA Container Toolkit
- NVIDIA GPU with 12GB+ VRAM (24GB recommended)
- NVIDIA drivers ≥ 530

### 1. Clone & Build

```bash
git clone https://github.com/JJPr-self/PLE_OS.git pleasuredai-os
cd pleasuredai-os

# Build the Docker image (~8-10 min on good internet)
docker build -t m842/pleasured_ai:latest .
```

### 2. Run Locally

```bash
docker compose up -d
```

### 3. Access

| Service              | URL                   |
| -------------------- | --------------------- |
| **NERV Dashboard**   | http://localhost:80   |
| **ComfyUI (direct)** | http://localhost:8188 |
| **NERV UI (direct)** | http://localhost:3000 |

Default login credentials are set via `AUTH_USERNAME` and `AUTH_PASSWORD` environment variables.

### 4. Download Models

```bash
# SSH into the container
docker exec -it nerv-genesis bash

# Download essential image models (~12GB)
/opt/scripts/get_models.sh --essential

# Download video models (~40GB+)
/opt/scripts/get_models.sh --video

# Download face swap models (~2GB)
/opt/scripts/get_models.sh --face

# Download everything
/opt/scripts/get_models.sh --all
```

---

## Building the Image

```bash
# Standard build
docker build -t pleasuredai/nerv-genesis:latest .

# Build with build cache for faster rebuilds
docker build --build-arg BUILDKIT_INLINE_CACHE=1 \
  -t pleasuredai/nerv-genesis:latest .

# Multi-platform (if needed)
docker buildx build --platform linux/amd64 \
  -t pleasuredai/nerv-genesis:latest .
```

**Build time:** ~8-10 minutes on a standard connection (most time is PyTorch + xFormers download).

---

## Deploying on vast.ai

### Step 1: Push Image to Registry

```bash
# Tag for Docker Hub
docker tag pleasuredai/nerv-genesis:latest <your-dockerhub>/nerv-genesis:latest

# Push
docker push <your-dockerhub>/nerv-genesis:latest
```

### Step 2: Create vast.ai Instance

| Setting             | Value                                  |
| ------------------- | -------------------------------------- |
| **Image**           | `<your-dockerhub>/nerv-genesis:latest` |
| **Docker Options**  | `-p 80:80 -p 8188:8188 -p 3000:3000`   |
| **Launch Mode**     | SSH (recommended)                      |
| **On-start Script** | `/root/onstart.sh`                     |
| **Disk Space**      | 100GB+ (for models)                    |
| **GPU**             | RTX 3090 or RTX 4090                   |

### Step 3: Environment Variables

```
AUTH_USERNAME=your_username
AUTH_PASSWORD=your_secure_password
HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxxx
```

### Step 4: Access

Find the external ports on the vast.ai console:

```
http://<IP>:<EXTERNAL_PORT_80>        # NERV Dashboard
http://<IP>:<EXTERNAL_PORT_8188>      # ComfyUI direct
```

### Step 5: Download Models (inside container)

```bash
# SSH into your vast.ai instance
ssh -p <SSH_PORT> root@<IP>

# Download models
/opt/scripts/get_models.sh --essential
/opt/scripts/get_models.sh --video
```

---

## Deploying on Other Cloud Hosts

### SSH + Remote Docker

```bash
# Deploy to a remote server with Docker + NVIDIA drivers
export DOCKER_HOST=ssh://user@your-server

# Build remotely
docker compose up -d --build

# Or transfer the image
docker save pleasuredai/nerv-genesis:latest | \
  ssh user@server 'docker load'
```

### RunPod / Lambda Labs

Same Docker image works. Set environment variables and port mappings as above.

---

## Model Downloads

### Recommended Model Sources

#### Image Models (Checkpoints)

| Model                | Size   | Source                                                                            | Why                                              |
| -------------------- | ------ | --------------------------------------------------------------------------------- | ------------------------------------------------ |
| **SDXL Base 1.0**    | 6.9GB  | [HuggingFace](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0)    | Best general-purpose, massive LoRA ecosystem     |
| **SDXL Refiner 1.0** | 6.1GB  | [HuggingFace](https://huggingface.co/stabilityai/stable-diffusion-xl-refiner-1.0) | Enhances SDXL detail in 2-pass generation        |
| **Juggernaut XL v9** | ~6.5GB | [CivitAI](https://civitai.com/models/133005)                                      | Photorealistic SDXL finetune, best for portraits |
| **DreamShaper XL**   | ~6.5GB | [CivitAI](https://civitai.com/models/112902)                                      | Versatile SDXL for illustration + photo          |

#### Video Models

| Model               | Size  | Source                                                      | Why                                         |
| ------------------- | ----- | ----------------------------------------------------------- | ------------------------------------------- |
| **WAN 2.2 T2V 14B** | ~28GB | [HuggingFace](https://huggingface.co/Wan-AI/Wan2.2-T2V-14B) | SOTA open-source video, best motion quality |
| **WAN 2.2 I2V 14B** | ~28GB | [HuggingFace](https://huggingface.co/Wan-AI/Wan2.2-I2V-14B) | Image-to-video animation                    |
| **LTX Video 2B**    | ~4GB  | [HuggingFace](https://huggingface.co/Lightricks/LTX-Video)  | Fast, lightweight, great for RTX 3090       |
| **CogVideoX-5B**    | ~10GB | [HuggingFace](https://huggingface.co/THUDM/CogVideoX-5b)    | Tencent's strong T2V, good motion           |

#### LoRA Models

| LoRA                  | Purpose                    | Source                                                                                        |
| --------------------- | -------------------------- | --------------------------------------------------------------------------------------------- |
| **SDXL Offset**       | Dramatic lighting/contrast | [HuggingFace (Stability AI)](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0) |
| **Detail Tweaker XL** | Control detail amount      | [CivitAI](https://civitai.com/models/122359)                                                  |
| **Add More Details**  | Sharpen/enhance            | [CivitAI](https://civitai.com/models/82098)                                                   |

#### VAE Models

| VAE                   | Purpose                            |
| --------------------- | ---------------------------------- |
| **SDXL VAE FP16 Fix** | Prevents black images in fp16 mode |

#### Face Swap Models

| Model                     | Purpose                         | Source                                                          |
| ------------------------- | ------------------------------- | --------------------------------------------------------------- |
| **InsightFace Buffalo L** | Face detection/recognition      | [HuggingFace](https://huggingface.co/datasets/Gourieff/ReActor) |
| **InSwapper 128**         | Core face swap model            | [HuggingFace](https://huggingface.co/datasets/Gourieff/ReActor) |
| **CodeFormer v0.1.0**     | Face restoration (best quality) | [HuggingFace](https://huggingface.co/datasets/Gourieff/ReActor) |
| **GFPGAN v1.4**           | Face restoration (alternative)  | [HuggingFace](https://huggingface.co/datasets/Gourieff/ReActor) |

---

## Using ComfyUI

### Text-to-Image (SDXL)

1. Open the NERV Dashboard → **GENERATE** tab
2. Select **Text → Image** mode
3. Choose **SDXL Base 1.0** model
4. Enter your prompt
5. Click **EXECUTE GENERATION**

Or use ComfyUI natively:

1. Go to **COMFYUI** tab (or port 8188 direct)
2. Load `txt2img_sdxl.json` from the workflow browser
3. Modify prompt → Click **Queue Prompt**

### Text-to-Video (WAN 2.2)

1. Ensure WAN 2.2 models are downloaded
2. Open ComfyUI → Load `txt2vid_wan22.json`
3. Set prompt, resolution (832×480 recommended for 24GB VRAM)
4. Queue prompt — generation takes 5-15 min at 30 steps

### Image-to-Video (LTX Video)

1. Upload source image to `/opt/comfyui/input/`
2. Open ComfyUI → Load `img2vid_ltx.json`
3. Select your input image
4. Set motion prompt and parameters
5. Queue prompt

### Video-to-Video

1. Extract frames from source video using Video Helper Suite nodes
2. Apply style transfer per-frame using img2img with ControlNet
3. Reassemble frames using VHS_VideoCombine node
4. Add motion smoothing with frame interpolation

---

## Face Swap & Deepfake Workflows

### Basic Face Swap (ReActor)

1. Download face swap models: `/opt/scripts/get_models.sh --face`
2. Open ComfyUI → Load `face_swap.json`
3. Set **source face** (the face you want) and **target image** (the image to modify)
4. Queue prompt — result has swapped face with CodeFormer restoration

### Face Consistency in Generation (InstantID)

1. Load a reference face image
2. Use InstantID node with SDXL
3. Generate new images maintaining facial identity
4. Combine with ControlNet for pose control

### Video Face Swap

1. Extract video frames → VHS nodes
2. Apply ReActor face swap per batch
3. Use CodeFormer restoration
4. Reassemble with audio mux

---

## Real-Time Webcam

> **Note:** Webcam capture requires browser access to the user's camera.

### Setup

1. Install webcam node: Already included via custom node installer
2. In ComfyUI, use the `WebcamCapture` node (from WAS Node Suite)
3. Connect webcam output to any image processing pipeline
4. Enable real-time preview

### Webcam + Face Swap Pipeline

1. `WebcamCapture` → `ReActorFaceSwap` → `PreviewImage`
2. Set webcam resolution to 512×512 for real-time speed
3. Use ONNX GPU runtime for fast face detection

---

## GPU Optimization Guide

### RTX 3090 (24GB VRAM)

| Setting      | Recommendation                        |
| ------------ | ------------------------------------- |
| Precision    | FP16 everywhere (saves 50% VRAM)      |
| VAE          | FP16 VAE with `sdxl_vae_fp16fix`      |
| xFormers     | Enabled (auto-detected)               |
| SDXL         | Full model fits in VRAM easily        |
| WAN 2.2 14B  | Fits in fp16, use 832×480, ≤81 frames |
| LTX Video    | Runs fast, can do 1280×720            |
| CogVideoX-5B | Fits in fp16                          |
| Batch size   | 1 for video, up to 4 for SDXL         |

### RTX 4090 (24GB VRAM)

Same VRAM as 3090 but with:

- **2-3x faster inference** (Ada Lovelace architecture)
- **CUDA Graph** support for repeated generations
- **BF16** support (better numerical stability than FP16)
- **FP8** support for even more VRAM savings

### Avoiding GPU OOM

1. **Use `--fp16-vae`** — Already default in our setup
2. **Enable tiled VAE** — For images larger than 1024×1024
3. **Reduce batch size** — Use 1 for video generation
4. **Lower resolution** — 832×480 for WAN, 768×768 for SDXL if tight
5. **Close other GPU processes** — Check with `nvidia-smi`
6. **Use `--lowvram` flag** — Moves model layers to CPU when not in use
7. **Restart ComfyUI** — Clears VRAM fragmentation

### Maximizing Throughput

1. **Queue multiple prompts** — ComfyUI processes sequentially
2. **Use LoRA instead of finetunes** — LoRAs are only ~100-300MB
3. **Cache models** — Don't switch models between prompts
4. **Use the right sampler** — DPM++ 2M Karras is fast + good quality
5. **Reduce steps** — 20-25 steps is usually sufficient for SDXL

---

## Security

### Default Credentials

**⚠️ There are NO hardcoded credentials in source code.**

Credentials are set at runtime via environment variables. The Docker image ships with fallback defaults (`nerv`/`genesis`) that are only used if you don't set `AUTH_USERNAME` and `AUTH_PASSWORD` env vars. **Always set custom credentials for cloud deployments.**

### Setting Custom Credentials

Via environment variables in docker-compose or vast.ai:

```yaml
environment:
  - AUTH_USERNAME=your_operator_id
  - AUTH_PASSWORD=your_secure_passphrase
  - AUTH_TOKEN=your_api_token_here
```

### Security Best Practices for Cloud

1. **Change default passwords** immediately
2. **Use SSH keys** instead of password auth on the VM
3. **Don't expose port 8188 directly** — use Nginx proxy on port 80
4. **Set HF_TOKEN** as an environment variable, not in files
5. **Monitor access logs**: `/var/log/nerv/nginx_access.log`
6. **Use vast.ai's SSH mode** instead of direct port exposure
7. **Rotate AUTH_TOKEN** periodically

---

## Pushing to Container Registry

### Docker Hub

```bash
# Login
docker login

# Tag
docker tag pleasuredai/nerv-genesis:latest your-username/nerv-genesis:latest

# Push
docker push your-username/nerv-genesis:latest
```

### GitHub Container Registry

```bash
# Login to ghcr.io
echo $GITHUB_TOKEN | docker login ghcr.io -u your-username --password-stdin

# Tag
docker tag pleasuredai/nerv-genesis:latest ghcr.io/your-username/nerv-genesis:latest

# Push
docker push ghcr.io/your-username/nerv-genesis:latest
```

### Private Registry

```bash
docker tag pleasuredai/nerv-genesis:latest your-registry.com/nerv-genesis:latest
docker push your-registry.com/nerv-genesis:latest
```

---

## Troubleshooting

### Container won't start on vast.ai

- Ensure `/root/onstart.sh` is set as the on-start script
- Check for port conflicts — vast.ai assigns dynamic external ports
- Use `docker logs nerv-genesis` or SSH in and check `/var/log/nerv/startup.log`

### GPU not detected

```bash
# Inside container:
nvidia-smi
python3 -c "import torch; print(torch.cuda.is_available())"
```

If fails: ensure NVIDIA Container Toolkit is installed on the host.

### ComfyUI won't load models

- Check model paths: `ls /opt/comfyui/models/checkpoints/`
- Verify `extra_model_paths.yaml` is correct
- Check ComfyUI logs: `cat /var/log/nerv/comfyui.log`

### Out of VRAM

```bash
# Check current usage
nvidia-smi

# Restart ComfyUI to clear fragmentation
# Via the NERV UI or:
kill $(pgrep -f "main.py")
cd /opt/comfyui && python3 main.py --listen 0.0.0.0 --port 8188 --lowvram --fp16-vae &
```

### Run GPU Test Suite

```bash
docker exec -it nerv-genesis /opt/scripts/test_gpu.sh
```

---

## File Structure

```
PLEASUREDAI OS/
├── Dockerfile                    # Main container image
├── docker-compose.yml            # Orchestration with volumes & GPU
├── entrypoint.sh                 # Startup: nodes, auth, services
├── scripts/
│   ├── get_models.sh             # Model download automation
│   ├── install_nodes.sh          # Custom node installer
│   ├── test_gpu.sh               # GPU verification suite
│   └── security_setup.sh         # Security hardening
├── nginx/
│   └── nginx.conf                # Reverse proxy + WebSocket
├── web-ui/
│   ├── index.html                # NERV dashboard
│   ├── style.css                 # Evangelion theme
│   └── app.js                    # Frontend logic
├── config/
│   ├── extra_model_paths.yaml    # ComfyUI model paths
│   ├── supervisord.conf          # Process manager config
│   └── .env.example              # Environment template
├── workflows/
│   ├── txt2img_sdxl.json         # Text-to-image (SDXL)
│   ├── txt2vid_wan22.json        # Text-to-video (WAN 2.2)
│   ├── img2vid_ltx.json          # Image-to-video (LTX)
│   └── face_swap.json            # Face swap (ReActor)
└── README.md                     # This file
```

---

## License

This project aggregates open-source tools. Individual model licenses apply:

- ComfyUI: GPL-3.0
- SDXL: Stability AI License
- WAN 2.2: Apache 2.0
- LTX Video: Lightricks License
- CogVideoX: Apache 2.0

**Use all models and tools responsibly and in accordance with their respective licenses.**
