#!/usr/bin/env bash
# 一键还原系统核心环境 (适用于 Debian/Ubuntu)
# 逻辑：强制 reinstall 基础包 + 清理非系统包
set -euo pipefail

log(){ printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

if [[ $EUID -ne 0 ]]; then
    err "请使用 root 权限运行"
    exit 1
fi

# --- 检测系统 ---
if [[ -f /etc/debian_version ]]; then
    if grep -qi ubuntu /etc/os-release; then
        DIST="ubuntu"
    else
        DIST="debian"
    fi
else
    err "未检测到 Debian/Ubuntu 系统"
    exit 1
fi
log "检测到系统: $DIST"

# --- 更新源 ---
log "更新 APT 源..."
apt-get update -y || true

# --- 基础包列表 ---
BASE_PKGS=()
if [[ "$DIST" == "ubuntu" ]]; then
    BASE_PKGS=(ubuntu-minimal ubuntu-standard)
else
    BASE_PKGS=(debian-minimal)
fi

# --- 强制重装基础包 ---
log "开始重装基础包: ${BASE_PKGS[*]}"
apt-get install --reinstall -y "${BASE_PKGS[@]}"

# --- 可选: 重新安装手动标记的包（官方推荐方式） ---
log "重装手动安装的基础包..."
apt-get install --reinstall -y $(apt-mark showmanual || true)

# --- 自动清理 ---
log "执行系统清理..."
apt-get autoremove --purge -y
apt-get clean

# --- 提示 ---
warn "还原完成，建议执行以下操作之一："
echo "  systemctl daemon-reexec   # 重新执行 systemd，不重启"
echo "  reboot                    # 安全起见，直接重启"

log "当前已安装核心包："
dpkg -l "${BASE_PKGS[@]}" || true
