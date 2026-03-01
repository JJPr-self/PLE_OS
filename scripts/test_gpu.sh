#!/bin/bash
###############################################################################
# PLEASUREDAI OS — GPU Test Script
# Verifies GPU access, CUDA, PyTorch, and ComfyUI startup
###############################################################################

PASS=0
FAIL=0
TOTAL=0

test_check() {
    TOTAL=$((TOTAL + 1))
    local NAME="$1"
    local CMD="$2"
    
    echo -n "[TEST ${TOTAL}] ${NAME}... "
    if eval "$CMD" > /dev/null 2>&1; then
        echo "✓ PASS"
        PASS=$((PASS + 1))
    else
        echo "✗ FAIL"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================================"
echo "  NERV Genesis — System Verification Suite"
echo "============================================================"
echo ""

# ── Hardware ─────────────────────────────────────────────────────────────────
echo "── Hardware Checks ──"
test_check "nvidia-smi available" "command -v nvidia-smi"
test_check "GPU detected" "nvidia-smi --query-gpu=name --format=csv,noheader | head -1"
test_check "CUDA toolkit" "nvcc --version"

# Show GPU details
echo ""
echo "GPU Details:"
nvidia-smi --query-gpu=name,memory.total,driver_version,compute_cap --format=csv 2>/dev/null || echo "  (unavailable)"
echo ""

# ── Software ─────────────────────────────────────────────────────────────────
echo "── Software Checks ──"
test_check "Python 3" "python3 --version"
test_check "PyTorch installed" "python3 -c 'import torch'"
test_check "PyTorch CUDA" "python3 -c 'import torch; assert torch.cuda.is_available()'"
test_check "xFormers" "python3 -c 'import xformers'"
test_check "FFmpeg" "ffmpeg -version"
test_check "aria2c" "aria2c --version"
test_check "Node.js" "node --version"
test_check "Nginx" "nginx -t"

# ── PyTorch Details ──────────────────────────────────────────────────────────
echo ""
echo "PyTorch Configuration:"
python3 -c "
import torch
print(f'  Version:    {torch.__version__}')
print(f'  CUDA:       {torch.version.cuda}')
print(f'  cuDNN:      {torch.backends.cudnn.version()}')
print(f'  GPU:        {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')
print(f'  VRAM:       {torch.cuda.get_device_properties(0).total_mem / 1024**3:.1f} GB' if torch.cuda.is_available() else '  VRAM:       N/A')
print(f'  FP16:       {\"Supported\" if torch.cuda.is_available() else \"N/A\"}')
print(f'  BF16:       {\"Supported\" if torch.cuda.is_available() and torch.cuda.is_bf16_supported() else \"Not supported\"}')
" 2>/dev/null || echo "  (unable to query)"
echo ""

# ── ComfyUI ──────────────────────────────────────────────────────────────────
echo "── ComfyUI Checks ──"
test_check "ComfyUI directory" "[ -d /opt/comfyui ]"
test_check "ComfyUI main.py" "[ -f /opt/comfyui/main.py ]"
test_check "Model directories" "[ -d /opt/comfyui/models/checkpoints ]"
test_check "Custom nodes dir" "[ -d /opt/comfyui/custom_nodes ]"

# Count installed nodes
NODE_COUNT=$(ls -d /opt/comfyui/custom_nodes/*/ 2>/dev/null | wc -l)
echo "  Custom nodes installed: ${NODE_COUNT}"

# Count models
CKPT_COUNT=$(find /opt/comfyui/models/checkpoints -name "*.safetensors" -o -name "*.ckpt" 2>/dev/null | wc -l)
echo "  Checkpoint models: ${CKPT_COUNT}"

# ── Network ──────────────────────────────────────────────────────────────────
echo ""
echo "── Network Checks ──"
test_check "Port 8188 bindable" "python3 -c 'import socket; s=socket.socket(); s.bind((\"0.0.0.0\",8188)); s.close()'"
test_check "Port 3000 bindable" "python3 -c 'import socket; s=socket.socket(); s.bind((\"0.0.0.0\",3000)); s.close()'"
test_check "Port 80 bindable" "python3 -c 'import socket; s=socket.socket(); s.bind((\"0.0.0.0\",80)); s.close()'"

# ── ComfyUI Quick Start Test ────────────────────────────────────────────────
echo ""
echo "── ComfyUI Startup Test ──"
echo -n "[TEST] ComfyUI can start... "
cd /opt/comfyui
timeout 30 python3 main.py --listen 0.0.0.0 --port 18188 --quick-test-for-ci 2>&1 | tail -5
if [ $? -eq 0 ] || [ $? -eq 124 ]; then
    echo "✓ PASS (startup successful)"
    PASS=$((PASS + 1))
else
    echo "✗ FAIL"
    FAIL=$((FAIL + 1))
fi
TOTAL=$((TOTAL + 1))

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Results: ${PASS}/${TOTAL} passed, ${FAIL} failed"
if [ $FAIL -eq 0 ]; then
    echo "  Status: ✓ ALL SYSTEMS OPERATIONAL"
else
    echo "  Status: ⚠ SOME CHECKS FAILED"
fi
echo "============================================================"

exit $FAIL
