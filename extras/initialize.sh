#!/bin/bash

# 系统清理脚本
# 仅删除明确的后装应用，保护所有系统通用组件
# 适用于 Debian/Ubuntu 系统

set -e

# 颜色和日志
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 检查权限并确认
[[ $EUID -ne 0 ]] && { echo "需要root权限: sudo $0"; exit 1; }

echo -e "${RED}警告: 将删除后装应用（Xray、1Panel、Docker等）${NC}"
read -p "确定继续？(输入 yes): " confirm
[[ "$(echo $confirm | tr '[:upper:]' '[:lower:]')" != "yes" ]] && { echo "操作已取消"; exit 0; }

echo "开始系统清理..."

# ==================== 第一步：清理后装应用文件 ====================

log "清理后装应用文件..."

# 明确的后装应用路径（只删除这些）
CLEANUP_PATHS=(
    # 代理工具
    "/usr/local/bin/xray"
    "/usr/local/bin/v2ray"
    "/usr/local/bin/v2ctl"
    "/usr/local/bin/sing-box"
    "/usr/local/bin/hysteria"
    "/usr/local/bin/hysteria2"
    "/usr/local/bin/hy2"
    "/usr/local/bin/clash"
    "/usr/local/bin/clash-meta"
    "/usr/local/bin/trojan"
    "/usr/local/bin/trojan-go"
    "/usr/local/bin/tuic"
    "/usr/bin/caddy"
    # 管理面板
    "/usr/local/bin/1panel"
    "/opt/1panel"
    "/opt/nezha"
    "/opt/ql"
    "/opt/portainer"
    "/opt/filebrowser"
    "/opt/frp"
    # 宝塔面板相关
    "/www/server/panel"
    "/www/server/bt-tasks"
    # 下载工具
    "/etc/aria2"
    # 配置目录
    "/etc/xray"
    "/etc/v2ray"
    "/etc/sing-box"
    "/etc/hysteria"
    "/etc/hysteria2"
    "/etc/clash"
    "/etc/trojan"
    "/etc/caddy"
    "/etc/frp"
    "/etc/1panel"
    "/etc/nezha"
    "/usr/local/etc/xray"
    "/usr/local/etc/v2ray"
    "/usr/local/etc/sing-box"
    "/usr/local/etc/clash"
    "/var/lib/1panel"
    # 日志目录
    "/var/log/xray"
    "/var/log/v2ray"
    "/var/log/sing-box"
    "/var/log/hysteria"
    "/var/log/nginx"
)

for path in "${CLEANUP_PATHS[@]}"; do
    [[ -e "$path" ]] && rm -rf "$path" 2>/dev/null && log "删除: $path"
done

# ==================== 第二步：清理后装服务 ====================

log "清理后装systemd服务..."

# 明确的后装应用服务名
CLEANUP_SERVICES=(
    "xray" "v2ray" "sing-box" "hysteria" "hysteria2" "hy2"
    "clash" "trojan" "caddy" "frps" "frpc" "1panel"
    "nezha-agent" "nezha-dashboard" "aria2" "filebrowser"
    "portainer" "docker" "containerd"
)

for service in "${CLEANUP_SERVICES[@]}"; do
    # 停止服务
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
    
    # 删除服务文件
    rm -f "/etc/systemd/system/${service}.service"
    rm -f "/etc/systemd/system/${service}d.service"
    rm -f "/etc/systemd/system/${service}-agent.service"
    rm -f "/etc/systemd/system/${service}-dashboard.service"
done

systemctl daemon-reload 2>/dev/null || true

# ==================== 第三步：杀死后装应用进程 ====================

log "终止后装应用进程..."

KILL_PATTERNS=(
    "xray" "v2ray" "sing-box" "hysteria" "clash" "trojan"
    "caddy" "frps" "frpc" "1panel" "nezha" "aria2"
    "filebrowser" "portainer" "docker" "containerd"
)

for pattern in "${KILL_PATTERNS[@]}"; do
    pkill -f "$pattern" 2>/dev/null || true
done

# ==================== 第四步：删除后装包（仅删除明确的后装包） ====================

log "删除后装APT包..."

# 只删除明确的后装包，绝不删除通用系统组件
REMOVE_PKGS=(
    "docker.io" "docker-ce" "docker-compose" "containerd.io"
    "docker-compose-plugin"
)

for pkg in "${REMOVE_PKGS[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        log "删除APT包: $pkg"
        apt remove --purge -y "$pkg" -qq 2>/dev/null || true
    fi
done

# ==================== 第五步：清理用户目录中的后装文件 ====================

log "清理用户目录..."

for home in /home/*/; do
    [[ -d "$home" ]] || continue
    
    # 只清理明确的后装应用配置
    rm -rf "${home}.config/1panel" 2>/dev/null || true
    rm -rf "${home}.config/clash" 2>/dev/null || true
    rm -rf "${home}.config/v2ray" 2>/dev/null || true
    rm -rf "${home}.xray" 2>/dev/null || true
    rm -rf "${home}.v2ray" 2>/dev/null || true
done

# ==================== 第六步：清理缓存（安全的清理） ====================

log "清理缓存..."

# 只清理明确的临时文件
rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null || true

# 清理apt缓存
apt autoclean 2>/dev/null || true
apt clean 2>/dev/null || true

# ==================== 第七步：验证系统完整性 ====================

log "验证系统完整性..."

# 检查并修复dpkg
dpkg --configure -a --force-confold 2>/dev/null || true

# 检查并修复apt
apt update -qq 2>/dev/null || {
    log "尝试修复APT..."
    apt install -f -y -qq 2>/dev/null || true
    apt update -qq 2>/dev/null || true
}

# 确保关键服务正常
for service in systemd-resolved systemd-networkd networking; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        systemctl restart "$service" 2>/dev/null || true
    fi
done

# ==================== 完成 ====================

success "系统清理完成！"
echo "已删除的内容："
echo "  - Xray、V2Ray、Sing-box、Hysteria2等代理工具"
echo "  - 1Panel、Nezha、Portainer等管理面板"
echo "  - Docker容器环境"
echo "  - Trojan、Caddy等网络工具"
echo ""
echo "系统组件已保留："
echo "  - Bash、Python、通用命令行工具"
echo "  - Systemd、网络管理"
echo "  - SSH、apt、dpkg"
echo ""
echo "建议重启系统: sudo reboot"
