#!/bin/bash
###############################################################################
# PLEASUREDAI OS — Security Setup
# Hardens the container for cloud deployment
###############################################################################

echo "[NERV:SEC] Applying security hardening..."

# ── Disable unnecessary services ─────────────────────────────────────────────
# Remove any default SSH that vast.ai might not need
# (vast.ai provides its own SSH layer)

# ── Set file permissions ─────────────────────────────────────────────────────
# Auth config readable only by root
chmod 600 /opt/nerv-ui/auth_config.json 2>/dev/null || true

# Scripts executable only by root
chmod 700 /opt/scripts/*.sh 2>/dev/null || true

# Log directory
chmod 750 /var/log/nerv 2>/dev/null || true

# ── Configure firewall rules (iptables) ──────────────────────────────────────
# Only if iptables is available (may not be in all container runtimes)
if command -v iptables &> /dev/null; then
    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
    # Allow our service ports
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 3000 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 8188 -j ACCEPT 2>/dev/null || true
fi

# ── Generate random secrets if not provided ──────────────────────────────────
if [ -z "$AUTH_TOKEN" ]; then
    AUTH_TOKEN=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
    echo "[NERV:SEC] Generated auth token (length: ${#AUTH_TOKEN})"
fi

# ── Disable Python bytecode caching (security) ──────────────────────────────
export PYTHONDONTWRITEBYTECODE=1

# ── Clear sensitive env vars from process listing ────────────────────────────
unset HF_TOKEN 2>/dev/null || true

echo "[NERV:SEC] ✓ Security hardening complete"
