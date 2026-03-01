#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════════════════════════
 NERV-AI — Command Line Interface
 PLEASUREDAI OS v1.0

 A unified CLI tool for managing the NERV Genesis system.
 Accessible from anywhere inside the container via `nerv-ai`.

 Usage:
   nerv-ai status          — System & GPU status overview
   nerv-ai logs [service]  — View/tail service logs
   nerv-ai errors          — Show recent errors across all services
   nerv-ai gpu             — Detailed GPU info (VRAM, temp, utilization)
   nerv-ai models          — List installed models by category
   nerv-ai nodes           — List installed custom nodes
   nerv-ai restart [svc]   — Restart a service (comfyui|nginx|ui|all)
   nerv-ai health          — Run full health check
   nerv-ai download <mode> — Download models (essential|video|face|all)
   nerv-ai comfyui <cmd>   — Send ComfyUI API commands
   nerv-ai config          — Show current configuration
   nerv-ai version         — Show version info
═══════════════════════════════════════════════════════════════════════════════
"""

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import time
import textwrap
from datetime import datetime, timedelta
from pathlib import Path

# ── Constants ────────────────────────────────────────────────────────────────
VERSION = "1.0.0"
COMFYUI_DIR = os.environ.get("COMFYUI_DIR", "/opt/comfyui")
MODELS_DIR = os.environ.get("MODELS_DIR", "/opt/comfyui/models")
CUSTOM_NODES_DIR = os.environ.get("CUSTOM_NODES_DIR", "/opt/comfyui/custom_nodes")
LOG_DIR = "/var/log/nerv"
COMFYUI_PORT = int(os.environ.get("COMFYUI_PORT", "8188"))
COMFYUI_URL = f"http://127.0.0.1:{COMFYUI_PORT}"

# ANSI Colors (Evangelion palette)
class C:
    PURPLE = "\033[38;5;135m"
    PINK = "\033[38;5;205m"
    RED = "\033[38;5;196m"
    GREEN = "\033[38;5;82m"
    YELLOW = "\033[38;5;220m"
    CYAN = "\033[38;5;87m"
    DIM = "\033[38;5;243m"
    BOLD = "\033[1m"
    RESET = "\033[0m"
    BG_PURPLE = "\033[48;5;53m"

BANNER = f"""{C.PURPLE}
 ███╗   ██╗███████╗██████╗ ██╗   ██╗     █████╗ ██╗
 ████╗  ██║██╔════╝██╔══██╗██║   ██║    ██╔══██╗██║
 ██╔██╗ ██║█████╗  ██████╔╝██║   ██║    ███████║██║
 ██║╚██╗██║██╔══╝  ██╔══██╗╚██╗ ██╔╝    ██╔══██║██║
 ██║ ╚████║███████╗██║  ██║ ╚████╔╝     ██║  ██║██║
 ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝  ╚═══╝      ╚═╝  ╚═╝╚═╝
{C.DIM} PLEASUREDAI OS — NERV Genesis CLI v{VERSION}{C.RESET}
"""

# ── Utility ──────────────────────────────────────────────────────────────────
def run_cmd(cmd, capture=True, timeout=30):
    """Run a shell command and return (returncode, stdout, stderr)."""
    try:
        r = subprocess.run(
            cmd, shell=True, capture_output=capture, text=True, timeout=timeout
        )
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired:
        return 1, "", "Command timed out"
    except Exception as e:
        return 1, "", str(e)

def http_get(path, timeout=5):
    """Simple HTTP GET to ComfyUI API."""
    import urllib.request
    try:
        url = f"{COMFYUI_URL}{path}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except Exception:
        return None

def print_header(title):
    """Print a styled section header."""
    print(f"\n{C.PURPLE}{'═' * 60}{C.RESET}")
    print(f" {C.PINK}{C.BOLD}{title}{C.RESET}")
    print(f"{C.PURPLE}{'═' * 60}{C.RESET}")

def print_kv(key, value, color=C.CYAN):
    """Print a key-value pair."""
    print(f"  {C.DIM}{key:<22}{C.RESET} {color}{value}{C.RESET}")

def print_ok(msg):
    print(f"  {C.GREEN}✓{C.RESET} {msg}")

def print_warn(msg):
    print(f"  {C.YELLOW}⚠{C.RESET} {msg}")

def print_err(msg):
    print(f"  {C.RED}✗{C.RESET} {msg}")

def format_bytes(b):
    """Human-readable byte size."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if b < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PB"

def get_dir_size(path):
    """Get total size of a directory."""
    total = 0
    p = Path(path)
    if p.exists():
        for f in p.rglob('*'):
            if f.is_file():
                total += f.stat().st_size
    return total

# ═══════════════════════════════════════════════════════════════════════════════
# STATUS COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_status(args):
    """Show system-wide status overview."""
    print(BANNER)
    print_header("SYSTEM STATUS")

    # Uptime
    rc, uptime_out, _ = run_cmd("uptime -p")
    print_kv("Uptime", uptime_out if rc == 0 else "Unknown")

    # Timestamp
    print_kv("Time", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

    # vast.ai detection
    public_ip = os.environ.get("PUBLIC_IPADDR", "")
    if public_ip:
        ext_port = os.environ.get("VAST_TCP_PORT_80", "80")
        print_kv("Environment", "vast.ai", C.PINK)
        print_kv("External URL", f"http://{public_ip}:{ext_port}")
    else:
        print_kv("Environment", "Standalone / Local")

    # Services
    print_header("SERVICES")
    services = {
        "ComfyUI": ("python3.*main.py", COMFYUI_PORT),
        "Nginx": ("nginx.*master", 80),
        "NERV UI": ("http.server.*3000", 3000),
    }
    for name, (proc_pattern, port) in services.items():
        rc, out, _ = run_cmd(f"pgrep -f '{proc_pattern}' | head -1")
        pid = out.strip() if rc == 0 and out.strip() else None
        if pid:
            print_ok(f"{name:<14} PID {pid:<8} port {port}")
        else:
            print_err(f"{name:<14} NOT RUNNING")

    # GPU quick summary
    print_header("GPU")
    cmd_gpu_brief()

    # Recent errors
    print_header("RECENT ERRORS (last 5)")
    errors = collect_errors(max_lines=5)
    if errors:
        for ts, svc, msg in errors:
            print(f"  {C.DIM}{ts}{C.RESET} {C.RED}[{svc}]{C.RESET} {msg[:80]}")
    else:
        print_ok("No recent errors")

    print()

# ═══════════════════════════════════════════════════════════════════════════════
# GPU COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_gpu(args):
    """Detailed GPU information."""
    print_header("GPU DETAILS")

    rc, out, _ = run_cmd(
        "nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,"
        "temperature.gpu,utilization.gpu,utilization.memory,power.draw,"
        "power.limit,driver_version,compute_cap "
        "--format=csv,noheader,nounits"
    )

    if rc != 0 or not out:
        print_err("nvidia-smi not available or no GPU detected")
        return

    for i, line in enumerate(out.split('\n')):
        fields = [f.strip() for f in line.split(',')]
        if len(fields) < 11:
            continue

        name, mem_total, mem_used, mem_free, temp, gpu_util, mem_util, \
            power, power_limit, driver, compute = fields

        print(f"\n  {C.PINK}GPU {i}{C.RESET}: {C.BOLD}{name}{C.RESET}")
        print_kv("Driver", driver)
        print_kv("Compute Cap", compute)
        print_kv("Temperature", f"{temp}°C", C.RED if int(temp) > 80 else C.GREEN)
        print_kv("GPU Utilization", f"{gpu_util}%")
        print_kv("VRAM Total", f"{mem_total} MiB")
        print_kv("VRAM Used", f"{mem_used} MiB ({int(int(mem_used)/int(mem_total)*100)}%)",
                 C.RED if int(mem_used)/int(mem_total) > 0.9 else C.CYAN)
        print_kv("VRAM Free", f"{mem_free} MiB")
        print_kv("Power Draw", f"{power}W / {power_limit}W")

    # PyTorch CUDA info
    print(f"\n  {C.PURPLE}─── PyTorch ───{C.RESET}")
    rc, out, _ = run_cmd(
        'python3 -c "'
        "import torch; "
        "print(f'Version: {torch.__version__}'); "
        "print(f'CUDA: {torch.version.cuda}'); "
        "print(f'cuDNN: {torch.backends.cudnn.version()}'); "
        "print(f'BF16: {torch.cuda.is_bf16_supported() if torch.cuda.is_available() else False}'); "
        "print(f'xFormers: ', end=''); "
        "try:\n import xformers; print(xformers.__version__)\n"
        "except: print('Not installed')"
        '"', timeout=15
    )
    if rc == 0:
        for line in out.split('\n'):
            k, _, v = line.partition(':')
            if v:
                print_kv(k.strip(), v.strip())

    print()

def cmd_gpu_brief():
    """Quick GPU summary (used inside status)."""
    rc, out, _ = run_cmd(
        "nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu,utilization.gpu "
        "--format=csv,noheader,nounits"
    )
    if rc != 0 or not out:
        print_err("GPU not available")
        return

    for line in out.split('\n'):
        f = [x.strip() for x in line.split(',')]
        if len(f) >= 5:
            name, used, total, temp, util = f[:5]
            pct = int(int(used) / int(total) * 100)
            bar = "█" * (pct // 5) + "░" * (20 - pct // 5)
            color = C.RED if pct > 90 else C.YELLOW if pct > 70 else C.GREEN
            print(f"  {C.BOLD}{name}{C.RESET}")
            print(f"  VRAM: {color}{bar}{C.RESET} {used}/{total} MiB ({pct}%)")
            print(f"  Temp: {temp}°C  |  Util: {util}%")

# ═══════════════════════════════════════════════════════════════════════════════
# LOGS COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_logs(args):
    """View or tail service logs."""
    log_files = {
        "comfyui": "comfyui.log",
        "comfyui-stdout": "comfyui_stdout.log",
        "comfyui-stderr": "comfyui_stderr.log",
        "nginx": "nginx_error.log",
        "nginx-access": "nginx_access.log",
        "ui": "ui.log",
        "ui-stdout": "ui_stdout.log",
        "startup": "startup.log",
        "supervisor": "supervisord.log",
        "nodes": "node_install.log",
    }

    service = args.service if hasattr(args, 'service') and args.service else None
    follow = args.follow if hasattr(args, 'follow') else False
    lines = args.lines if hasattr(args, 'lines') else 50

    if service and service in log_files:
        log_path = os.path.join(LOG_DIR, log_files[service])
        if not os.path.exists(log_path):
            print_warn(f"Log file not found: {log_path}")
            return
        if follow:
            print(f"{C.DIM}Following {log_path} (Ctrl+C to stop)...{C.RESET}\n")
            os.execvp("tail", ["tail", "-f", "-n", str(lines), log_path])
        else:
            rc, out, _ = run_cmd(f"tail -n {lines} '{log_path}'", timeout=10)
            if rc == 0:
                print(out)
            else:
                print_err(f"Failed to read log: {log_path}")
    elif service:
        print_err(f"Unknown service: {service}")
        print(f"  Available: {', '.join(sorted(log_files.keys()))}")
    else:
        # List all available logs
        print_header("AVAILABLE LOGS")
        for name, filename in sorted(log_files.items()):
            path = os.path.join(LOG_DIR, filename)
            if os.path.exists(path):
                size = os.path.getsize(path)
                mtime = datetime.fromtimestamp(os.path.getmtime(path))
                line_count_rc, line_count, _ = run_cmd(f"wc -l < '{path}'")
                lc = line_count.strip() if line_count_rc == 0 else "?"
                print(f"  {C.CYAN}{name:<18}{C.RESET} {format_bytes(size):>10}  "
                      f"{lc:>6} lines  {C.DIM}{mtime:%H:%M:%S}{C.RESET}")
            else:
                print(f"  {C.DIM}{name:<18} (not created yet){C.RESET}")
        print(f"\n  Usage: {C.PINK}nerv-ai logs <service>{C.RESET} [-f] [-n 100]")

# ═══════════════════════════════════════════════════════════════════════════════
# ERRORS COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def collect_errors(max_lines=20):
    """Scan all log files for error patterns and return sorted list."""
    error_patterns = [
        r'\b(error|exception|traceback|failed|fatal|critical|panic)\b',
        r'(oom|out of memory|cuda error|segfault)',
        r'(errno|permission denied|connection refused)',
    ]
    combined_pattern = '|'.join(error_patterns)

    errors = []
    log_files = {
        "comfyui": ["comfyui.log", "comfyui_stdout.log", "comfyui_stderr.log"],
        "nginx": ["nginx_error.log"],
        "startup": ["startup.log"],
        "supervisor": ["supervisord.log"],
        "nodes": ["node_install.log"],
    }

    for svc, files in log_files.items():
        for fname in files:
            fpath = os.path.join(LOG_DIR, fname)
            if not os.path.exists(fpath):
                continue
            try:
                # Read last 500 lines only for performance
                rc, out, _ = run_cmd(f"tail -n 500 '{fpath}'", timeout=5)
                if rc != 0:
                    continue
                for line in out.split('\n'):
                    if re.search(combined_pattern, line, re.IGNORECASE):
                        # Try to extract timestamp
                        ts_match = re.match(r'(\d{4}[-/]\d{2}[-/]\d{2}\s+\d{2}:\d{2}:\d{2})', line)
                        ts = ts_match.group(1) if ts_match else "          "
                        # Clean the line
                        clean_line = line.strip()
                        if clean_line and len(clean_line) > 5:
                            errors.append((ts, svc, clean_line))
            except Exception:
                continue

    # Sort by timestamp descending, return last N
    errors.sort(key=lambda x: x[0], reverse=True)
    return errors[:max_lines]

def cmd_errors(args):
    """Show recent errors across all services."""
    max_lines = args.lines if hasattr(args, 'lines') else 30
    print_header(f"ERRORS (last {max_lines})")

    errors = collect_errors(max_lines)
    if not errors:
        print_ok("No errors found in recent logs")
        return

    current_svc = None
    for ts, svc, msg in errors:
        if svc != current_svc:
            print(f"\n  {C.PURPLE}── {svc.upper()} ──{C.RESET}")
            current_svc = svc

        # Colorize severity
        if re.search(r'(?i)(fatal|critical|panic|oom)', msg):
            color = C.RED
            icon = "🔴"
        elif re.search(r'(?i)(error|exception|traceback)', msg):
            color = C.RED
            icon = "❌"
        else:
            color = C.YELLOW
            icon = "⚠️"

        # Truncate long messages
        display_msg = msg[:120] + "..." if len(msg) > 120 else msg
        print(f"  {icon} {C.DIM}{ts}{C.RESET} {color}{display_msg}{C.RESET}")

    print(f"\n  {C.DIM}Total: {len(errors)} error(s) found{C.RESET}")
    print(f"  {C.DIM}Tip: Use `nerv-ai logs <service>` for full context{C.RESET}")
    print()

# ═══════════════════════════════════════════════════════════════════════════════
# MODELS COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_models(args):
    """List installed models by category."""
    print_header("INSTALLED MODELS")

    categories = {
        "Checkpoints": "checkpoints",
        "VAE": "vae",
        "LoRAs": "loras",
        "Embeddings": "embeddings",
        "ControlNet": "controlnet",
        "Upscale": "upscale_models",
        "CLIP": "clip",
        "CLIP Vision": "clip_vision",
        "Diffusion Models": "diffusion_models",
        "Text Encoders": "text_encoders",
        "UNet": "unet",
        "InsightFace": "insightface",
        "Face Restore": "facerestore_models",
        "Ultralytics": "ultralytics",
    }

    model_extensions = {'.safetensors', '.ckpt', '.pt', '.pth', '.bin', '.onnx'}
    grand_total = 0
    grand_size = 0

    for cat_name, subdir in categories.items():
        cat_path = os.path.join(MODELS_DIR, subdir)
        if not os.path.exists(cat_path):
            continue

        models = []
        for root, dirs, files in os.walk(cat_path):
            for f in files:
                ext = os.path.splitext(f)[1].lower()
                if ext in model_extensions:
                    fpath = os.path.join(root, f)
                    fsize = os.path.getsize(fpath)
                    rel = os.path.relpath(fpath, cat_path)
                    models.append((rel, fsize))

        if models:
            total_size = sum(s for _, s in models)
            grand_total += len(models)
            grand_size += total_size
            print(f"\n  {C.PINK}{cat_name}{C.RESET} ({len(models)} models, {format_bytes(total_size)})")
            for name, size in sorted(models):
                print(f"    {C.CYAN}•{C.RESET} {name:<50} {C.DIM}{format_bytes(size)}{C.RESET}")

    print(f"\n  {C.BOLD}Total: {grand_total} models ({format_bytes(grand_size)}){C.RESET}")
    print(f"  {C.DIM}Download more: nerv-ai download <essential|video|face|all>{C.RESET}\n")

# ═══════════════════════════════════════════════════════════════════════════════
# NODES COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_nodes(args):
    """List installed custom nodes."""
    print_header("CUSTOM NODES")

    nodes_path = Path(CUSTOM_NODES_DIR)
    if not nodes_path.exists():
        print_err(f"Custom nodes directory not found: {CUSTOM_NODES_DIR}")
        return

    nodes = []
    for d in sorted(nodes_path.iterdir()):
        if d.is_dir() and not d.name.startswith('.') and d.name != '__pycache__':
            # Try to get git remote URL
            git_dir = d / '.git'
            url = ""
            if git_dir.exists():
                rc, out, _ = run_cmd(f"git -C '{d}' remote get-url origin 2>/dev/null")
                url = out.strip() if rc == 0 else ""

            # Check for requirements.txt
            has_reqs = (d / 'requirements.txt').exists()

            # Check for __init__.py (valid node)
            has_init = (d / '__init__.py').exists()

            nodes.append((d.name, url, has_reqs, has_init))

    valid = [n for n in nodes if n[3]]
    invalid = [n for n in nodes if not n[3]]

    print(f"\n  {C.GREEN}Active Nodes ({len(valid)}){C.RESET}")
    for name, url, has_reqs, _ in valid:
        short_url = url.replace("https://github.com/", "") if url else ""
        print(f"    {C.CYAN}✓{C.RESET} {name:<45} {C.DIM}{short_url}{C.RESET}")

    if invalid:
        print(f"\n  {C.YELLOW}Inactive / No __init__.py ({len(invalid)}){C.RESET}")
        for name, url, has_reqs, _ in invalid:
            print(f"    {C.DIM}?{C.RESET} {name}")

    print(f"\n  {C.BOLD}Total: {len(nodes)} packages ({len(valid)} active){C.RESET}")
    print(f"  {C.DIM}Manage via ComfyUI Manager in the web UI{C.RESET}\n")

# ═══════════════════════════════════════════════════════════════════════════════
# RESTART COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_restart(args):
    """Restart a service."""
    service = args.service if hasattr(args, 'service') and args.service else 'comfyui'

    restart_cmds = {
        "comfyui": [
            ("Stopping ComfyUI...", "pkill -f 'python3.*main.py'"),
            ("Starting ComfyUI...", "cd /opt/comfyui && nohup python3 main.py "
             "--listen 0.0.0.0 --port 8188 --preview-method auto --fp16-vae "
             "> /var/log/nerv/comfyui.log 2>&1 &"),
        ],
        "nginx": [
            ("Reloading Nginx...", "nginx -s reload"),
        ],
        "ui": [
            ("Stopping NERV UI...", "pkill -f 'http.server.*3000'"),
            ("Starting NERV UI...", "cd /opt/nerv-ui && nohup python3 -m http.server 3000 "
             "--bind 0.0.0.0 > /var/log/nerv/ui.log 2>&1 &"),
        ],
        "all": None,  # handled below
    }

    if service == "all":
        for svc in ["nginx", "ui", "comfyui"]:
            print(f"\n  {C.PINK}Restarting {svc}...{C.RESET}")
            for desc, cmd in restart_cmds[svc]:
                print(f"  {C.DIM}{desc}{C.RESET}")
                run_cmd(cmd)
                time.sleep(1)
        print_ok("All services restarted")
        return

    if service not in restart_cmds:
        print_err(f"Unknown service: {service}")
        print(f"  Available: {', '.join(restart_cmds.keys())}")
        return

    print(f"\n  {C.PINK}Restarting {service}...{C.RESET}")
    for desc, cmd in restart_cmds[service]:
        print(f"  {C.DIM}{desc}{C.RESET}")
        rc, _, err = run_cmd(cmd)
        if rc != 0 and err:
            print_warn(f"  {err}")
        time.sleep(1)

    print_ok(f"{service} restarted")
    print()

# ═══════════════════════════════════════════════════════════════════════════════
# HEALTH COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_health(args):
    """Run comprehensive health check."""
    print_header("HEALTH CHECK")
    passed = 0
    failed = 0

    checks = [
        ("nvidia-smi available", "command -v nvidia-smi"),
        ("GPU detected", "nvidia-smi --query-gpu=name --format=csv,noheader | head -1"),
        ("PyTorch CUDA", "python3 -c 'import torch; assert torch.cuda.is_available()'"),
        ("xFormers", "python3 -c 'import xformers'"),
        ("FFmpeg", "ffmpeg -version"),
        ("ComfyUI directory", "test -d /opt/comfyui"),
        ("ComfyUI main.py", "test -f /opt/comfyui/main.py"),
        ("Model dirs", "test -d /opt/comfyui/models/checkpoints"),
        ("Nginx config valid", "nginx -t"),
        ("ComfyUI API reachable", f"curl -sf {COMFYUI_URL}/system_stats > /dev/null"),
        ("Disk space > 5GB", "python3 -c 'import shutil; assert shutil.disk_usage(\"/\").free > 5*1024**3'"),
    ]

    for name, cmd in checks:
        rc, _, _ = run_cmd(cmd, timeout=10)
        if rc == 0:
            print_ok(name)
            passed += 1
        else:
            print_err(name)
            failed += 1

    # Summary
    total = passed + failed
    color = C.GREEN if failed == 0 else C.YELLOW if failed <= 2 else C.RED
    print(f"\n  {color}{C.BOLD}Results: {passed}/{total} passed, {failed} failed{C.RESET}")
    if failed == 0:
        print(f"  {C.GREEN}All systems operational ✓{C.RESET}")
    print()

# ═══════════════════════════════════════════════════════════════════════════════
# DOWNLOAD COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_download(args):
    """Download models via get_models.sh."""
    mode = args.mode if hasattr(args, 'mode') and args.mode else 'essential'
    script = "/opt/scripts/get_models.sh"
    if not os.path.exists(script):
        print_err(f"Download script not found: {script}")
        return
    print(f"  {C.PINK}Starting model download (mode: --{mode})...{C.RESET}\n")
    os.execvp("bash", ["bash", script, f"--{mode}"])

# ═══════════════════════════════════════════════════════════════════════════════
# COMFYUI COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_comfyui(args):
    """Interact with ComfyUI API."""
    action = args.action if hasattr(args, 'action') and args.action else 'info'

    if action == 'info' or action == 'stats':
        data = http_get('/system_stats')
        if data:
            print_header("COMFYUI SYSTEM STATS")
            print(json.dumps(data, indent=2))
        else:
            print_err("Cannot reach ComfyUI API — service may not be running")

    elif action == 'queue':
        data = http_get('/queue')
        if data:
            running = len(data.get('queue_running', []))
            pending = len(data.get('queue_pending', []))
            print_header("COMFYUI QUEUE")
            print_kv("Running", str(running))
            print_kv("Pending", str(pending))
        else:
            print_err("Cannot reach ComfyUI API")

    elif action == 'history':
        data = http_get('/history?max_items=10')
        if data:
            print_header("RECENT HISTORY (last 10)")
            for prompt_id, info in list(data.items())[:10]:
                status = info.get('status', {})
                completed = status.get('completed', False)
                status_text = f"{C.GREEN}completed{C.RESET}" if completed else f"{C.YELLOW}incomplete{C.RESET}"
                print(f"  {C.DIM}{prompt_id[:12]}...{C.RESET}  {status_text}")
        else:
            print_err("Cannot reach ComfyUI API")

    elif action == 'clear':
        import urllib.request
        try:
            req = urllib.request.Request(f"{COMFYUI_URL}/queue", method='POST',
                                         data=json.dumps({"clear": True}).encode(),
                                         headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=5)
            print_ok("Queue cleared")
        except Exception as e:
            print_err(f"Failed to clear queue: {e}")

    elif action == 'interrupt':
        import urllib.request
        try:
            req = urllib.request.Request(f"{COMFYUI_URL}/interrupt", method='POST')
            urllib.request.urlopen(req, timeout=5)
            print_ok("Current generation interrupted")
        except Exception as e:
            print_err(f"Failed to interrupt: {e}")

    else:
        print_err(f"Unknown action: {action}")
        print(f"  Available: info, queue, history, clear, interrupt")

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_config(args):
    """Show current configuration."""
    print_header("CONFIGURATION")

    env_vars = [
        ("COMFYUI_DIR", COMFYUI_DIR),
        ("MODELS_DIR", MODELS_DIR),
        ("CUSTOM_NODES_DIR", CUSTOM_NODES_DIR),
        ("COMFYUI_PORT", str(COMFYUI_PORT)),
        ("NERV_UI_PORT", os.environ.get("NERV_UI_PORT", "3000")),
        ("AUTH_USERNAME", os.environ.get("AUTH_USERNAME", "nerv")),
        ("AUTH_PASSWORD", "****" if os.environ.get("AUTH_PASSWORD") else "(default)"),
        ("HF_TOKEN", "****" if os.environ.get("HF_TOKEN") else "(not set)"),
        ("PUBLIC_IPADDR", os.environ.get("PUBLIC_IPADDR", "(not set)")),
        ("CUDA_VISIBLE_DEVICES", os.environ.get("CUDA_VISIBLE_DEVICES", "all")),
        ("NVIDIA_VISIBLE_DEVICES", os.environ.get("NVIDIA_VISIBLE_DEVICES", "all")),
    ]

    for key, val in env_vars:
        print_kv(key, val)

    # Disk usage
    print(f"\n  {C.PURPLE}─── Storage ───{C.RESET}")
    for label, path in [("Models", MODELS_DIR), ("Output", "/opt/comfyui/output"),
                         ("Nodes", CUSTOM_NODES_DIR), ("HF Cache", "/root/.cache/huggingface")]:
        size = get_dir_size(path) if os.path.exists(path) else 0
        print_kv(label, format_bytes(size))

    rc, out, _ = run_cmd("df -h / | tail -1 | awk '{print $4}'")
    print_kv("Disk Free", out if rc == 0 else "?")
    print()

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION COMMAND
# ═══════════════════════════════════════════════════════════════════════════════
def cmd_version(args):
    """Show version info."""
    print(BANNER)
    print_kv("NERV-AI CLI", VERSION)

    # ComfyUI version
    rc, out, _ = run_cmd(f"cd {COMFYUI_DIR} && git log -1 --format='%h %s' 2>/dev/null")
    print_kv("ComfyUI", out if rc == 0 else "Unknown")

    # Python
    rc, out, _ = run_cmd("python3 --version")
    print_kv("Python", out if rc == 0 else "Unknown")

    # PyTorch
    rc, out, _ = run_cmd("python3 -c 'import torch; print(torch.__version__)'")
    print_kv("PyTorch", out if rc == 0 else "Unknown")

    # CUDA
    rc, out, _ = run_cmd("nvcc --version | tail -1")
    print_kv("CUDA Toolkit", out if rc == 0 else "Unknown")

    print()

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN — argparse CLI
# ═══════════════════════════════════════════════════════════════════════════════
def main():
    parser = argparse.ArgumentParser(
        prog='nerv-ai',
        description='NERV Genesis — AI System CLI',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(f"""\
            {C.PURPLE}Examples:{C.RESET}
              nerv-ai status             Full system overview
              nerv-ai logs comfyui -f    Follow ComfyUI logs live
              nerv-ai errors             Show recent errors across all services
              nerv-ai gpu                Detailed GPU info
              nerv-ai models             List installed AI models
              nerv-ai restart comfyui    Restart ComfyUI
              nerv-ai health             Run full health check
              nerv-ai download video     Download video models
              nerv-ai comfyui queue      Show ComfyUI queue status
              nerv-ai comfyui interrupt  Interrupt current generation
        """)
    )
    subparsers = parser.add_subparsers(dest='command')

    # status
    subparsers.add_parser('status', help='System status overview')

    # gpu
    subparsers.add_parser('gpu', help='Detailed GPU information')

    # logs
    p_logs = subparsers.add_parser('logs', help='View service logs')
    p_logs.add_argument('service', nargs='?', default=None,
                        help='Service name (comfyui, nginx, ui, startup, supervisor, nodes)')
    p_logs.add_argument('-f', '--follow', action='store_true', help='Follow log output')
    p_logs.add_argument('-n', '--lines', type=int, default=50, help='Number of lines')

    # errors
    p_errors = subparsers.add_parser('errors', help='Show recent errors')
    p_errors.add_argument('-n', '--lines', type=int, default=30, help='Max errors to show')

    # models
    subparsers.add_parser('models', help='List installed models')

    # nodes
    subparsers.add_parser('nodes', help='List installed custom nodes')

    # restart
    p_restart = subparsers.add_parser('restart', help='Restart a service')
    p_restart.add_argument('service', nargs='?', default='comfyui',
                           help='Service (comfyui, nginx, ui, all)')

    # health
    subparsers.add_parser('health', help='Run health check')

    # download
    p_dl = subparsers.add_parser('download', help='Download models')
    p_dl.add_argument('mode', nargs='?', default='essential',
                      help='Download mode (essential, video, face, loras, controlnet, all)')

    # comfyui
    p_comfy = subparsers.add_parser('comfyui', help='ComfyUI API commands')
    p_comfy.add_argument('action', nargs='?', default='info',
                         help='Action (info, queue, history, clear, interrupt)')

    # config
    subparsers.add_parser('config', help='Show configuration')

    # version
    subparsers.add_parser('version', help='Show version info')

    args = parser.parse_args()

    if not args.command:
        cmd_status(args)
        return

    commands = {
        'status': cmd_status,
        'gpu': cmd_gpu,
        'logs': cmd_logs,
        'errors': cmd_errors,
        'models': cmd_models,
        'nodes': cmd_nodes,
        'restart': cmd_restart,
        'health': cmd_health,
        'download': cmd_download,
        'comfyui': cmd_comfyui,
        'config': cmd_config,
        'version': cmd_version,
    }

    handler = commands.get(args.command)
    if handler:
        handler(args)
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
