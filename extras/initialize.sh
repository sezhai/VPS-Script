#!/bin/bash

# 系统清理脚本
# 适用于 Debian/Ubuntu 系统

set -e

# 颜色和日志
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 检查权限并确认
[[ $EUID -ne 0 ]] && { echo "需要root权限: sudo $0"; exit 1; }

echo -e "${RED}警告: 将永久删除所有后装应用！${NC}"
read -p "确定继续？(输入 yes): " confirm
[[ "$(echo $confirm | tr '[:upper:]' '[:lower:]')" != "yes" ]] && { echo "操作已取消"; exit 0; }

echo "开始系统清理..."

# 停止服务并清理systemd
log "清理系统服务..."
for service in /etc/systemd/system/*.service; do
    [[ -f "$service" ]] || continue
    name=$(basename "$service")
    # 跳过系统关键服务
    [[ "$name" =~ ^(getty|network|ssh|cron|rsyslog|systemd-) ]] && continue
    systemctl stop "$name" 2>/dev/null || true
    systemctl disable "$name" 2>/dev/null || true
    rm -f "$service"
done
rm -rf /etc/systemd/system/*.{wants,requires}/ 2>/dev/null || true
systemctl daemon-reload

# 清理常见后装应用
log "清理后装应用..."
APPS=(
    "xray:/usr/local/bin/xray:/etc/xray:/usr/local/etc/xray"
    "v2ray:/usr/local/bin/v2ray:/etc/v2ray:/usr/local/etc/v2ray"
    "sing-box:/usr/local/bin/sing-box:/etc/sing-box"
    "hysteria:/usr/local/bin/hysteria:/etc/hysteria"
    "hysteria2:/usr/local/bin/hysteria2:/etc/hysteria2"
    "hy2:/usr/local/bin/hy2"
    "clash:/usr/local/bin/clash:/etc/clash"
    "1panel:/usr/local/bin/1panel:/opt/1panel:/etc/1panel"
    "nezha-agent:/opt/nezha"
    "nezha-dashboard:/opt/nezha"
    "trojan:/usr/local/bin/trojan"
    "caddy:/usr/bin/caddy:/etc/caddy"
    "frps:/opt/frp:/etc/frp"
    "frpc:/opt/frp:/etc/frp"
)

for app_info in "${APPS[@]}"; do
    IFS=':' read -ra PARTS <<< "$app_info"
    app_name="${PARTS[0]}"
    
    # 停止服务
    for service_name in "$app_name" "${app_name}s" "${app_name}-agent" "${app_name}-dashboard"; do
        systemctl stop "$service_name" 2>/dev/null || true
        systemctl disable "$service_name" 2>/dev/null || true
        rm -f "/etc/systemd/system/${service_name}.service"
    done
    
    # 删除文件和目录
    for i in $(seq 1 $((${#PARTS[@]}-1))); do
        rm -rf "${PARTS[$i]}" 2>/dev/null || true
    done
    
    # 终止进程
    pkill -f "$app_name" 2>/dev/null || true
done

# 清理面板数据
rm -rf /www/server/{panel,bt-tasks} /var/lib/{docker,containerd,portainer} 2>/dev/null || true

# 清理安装目录
log "清理安装目录..."
rm -rf /opt/* 2>/dev/null || true

# 清理用户程序
for home in /home/*/; do
    [[ -d "$home" ]] || continue
    rm -rf "${home}.local/bin"/* "${home}.cache"/* 2>/dev/null || true
    find "${home}.local/share/applications" -name "*.desktop" -delete 2>/dev/null || true
done

# 清理手动安装的工具
TOOLS=(htop btop tree nano vim tmux screen git curl wget rsync docker docker-compose
       node npm python3 pip go ffmpeg youtube-dl yt-dlp kubectl helm terraform)
for tool in "${TOOLS[@]}"; do
    rm -f "/usr/local/bin/$tool" "/usr/bin/$tool" 2>/dev/null || true
done

# 重置APT包
log "重置APT包..."
apt update -qq

# 保护关键包
PROTECTED="sudo|openssh|systemd|network|netplan|kernel|linux-|grub|libc6|init|base-"
REMOVE_PKGS=(htop tree nano vim neovim tmux screen git curl wget rsync p7zip-full unrar 
             ffmpeg nodejs npm python3-pip docker.io docker-ce containerd.io nginx apache2 
             mysql-server mariadb-server postgresql redis-server php zsh fish neofetch 
             btop nload iftop glances speedtest-cli build-essential make cmake gcc g++)

for pkg in "${REMOVE_PKGS[@]}"; do
    [[ "$pkg" =~ $PROTECTED ]] && continue
    dpkg -l 2>/dev/null | grep -q "^ii.*$pkg" && {
        apt remove --purge -y "$pkg" -qq 2>/dev/null || true
    }
done

# 设置基础包
if command -v ubuntu-minimal >/dev/null 2>&1; then
    BASE="ubuntu-minimal ubuntu-standard"
else
    BASE="base-files base-passwd bash coreutils apt"
fi
BASE="$BASE sudo openssh-server systemd-resolved netplan.io"

# 标记包并清理
dpkg --get-selections | awk '/install$/{print $1}' | xargs apt-mark auto 2>/dev/null || true
apt-mark manual $BASE 2>/dev/null || true
apt autoremove --purge -y -qq
apt clean

# 清理缓存和临时文件
log "清理缓存..."
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
find /usr/share/applications -name "*.desktop" -not -path "*/dpkg/*" -delete 2>/dev/null || true

# 更新系统组件
log "更新系统组件..."
update-initramfs -u >/dev/null 2>&1 || true
command -v update-grub >/dev/null && update-grub >/dev/null 2>&1 || true

success "系统清理完成！建议重启: reboot"
