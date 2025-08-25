#!/bin/bash

# 系统清理脚本 - 优化精简版
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
    "xray:/usr/local/bin/xray:/etc/xray:/usr/local/etc/xray:/var/log/xray"
    "v2ray:/usr/local/bin/v2ray:/etc/v2ray:/usr/local/etc/v2ray:/var/log/v2ray"
    "sing-box:/usr/local/bin/sing-box:/etc/sing-box:/usr/local/etc/sing-box:/var/log/sing-box"
    "hysteria:/usr/local/bin/hysteria:/etc/hysteria:/var/log/hysteria"
    "hysteria2:/usr/local/bin/hysteria2:/etc/hysteria2:/var/log/hysteria2"
    "hy2:/usr/local/bin/hy2:/etc/hy2"
    "clash:/usr/local/bin/clash:/etc/clash:/usr/local/etc/clash"
    "clash-meta:/usr/local/bin/clash-meta"
    "1panel:/usr/local/bin/1panel:/opt/1panel:/etc/1panel:/var/lib/1panel"
    "nezha-agent:/opt/nezha:/etc/nezha"
    "nezha-dashboard:/opt/nezha"
    "trojan:/usr/local/bin/trojan:/etc/trojan"
    "trojan-go:/usr/local/bin/trojan-go"
    "caddy:/usr/bin/caddy:/etc/caddy:/var/lib/caddy"
    "nginx:/usr/local/nginx:/var/log/nginx"
    "frps:/opt/frp:/etc/frp"
    "frpc:/opt/frp:/etc/frp"
    "docker:/var/lib/docker:/etc/docker"
    "containerd:/var/lib/containerd:/etc/containerd"
    "portainer:/var/lib/portainer:/opt/portainer"
    "qinglong:/opt/ql"
    "aria2:/etc/aria2"
    "filebrowser:/opt/filebrowser"
    "rclone:/usr/local/bin/rclone"
    "bt:/www/server/panel:/www/server/bt-tasks"
    "aapanel:/www/server/panel"
)

for app_info in "${APPS[@]}"; do
    IFS=':' read -ra PARTS <<< "$app_info"
    app_name="${PARTS[0]}"
    
    # 停止相关服务（支持多种服务名格式）
    for service_name in "$app_name" "${app_name}s" "${app_name}-agent" "${app_name}-dashboard" "${app_name}d" "${app_name}.service"; do
        systemctl stop "$service_name" 2>/dev/null || true
        systemctl disable "$service_name" 2>/dev/null || true
        rm -f "/etc/systemd/system/${service_name}" "/etc/systemd/system/${service_name}.service"
    done
    
    # 删除文件和目录
    for i in $(seq 1 $((${#PARTS[@]}-1))); do
        rm -rf "${PARTS[$i]}" 2>/dev/null || true
    done
    
    # 终止进程
    pkill -f "$app_name" 2>/dev/null || true
done

# 清理面板数据和容器数据
log "清理数据目录..."
rm -rf /www/server/{panel,bt-tasks} /var/lib/{docker,containerd,portainer,snapd,flatpak} 2>/dev/null || true
rm -rf /snap /var/snap 2>/dev/null || true

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

# 预先修复dpkg问题
log "检查并修复dpkg状态..."
if ! dpkg --audit >/dev/null 2>&1; then
    log "修复损坏的dpkg包..."
    
    # 修复常见的损坏包
    BROKEN_PACKAGES=("cloud-init" "ssh-import-id")
    for pkg in "${BROKEN_PACKAGES[@]}"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^.i"; then
            log "修复损坏的包: $pkg"
            # 创建临时脚本绕过错误
            for script in /var/lib/dpkg/info/${pkg}.{prerm,postinst,postrm}; do
                if [[ -f "$script" ]] && ! bash -n "$script" 2>/dev/null; then
                    echo -e "#!/bin/bash\nexit 0" > "$script"
                    chmod +x "$script"
                fi
            done
        fi
    done
    
    # 尝试配置
    dpkg --configure -a --force-confold 2>/dev/null || true
fi

apt update -qq 2>/dev/null || {
    log "apt update失败，尝试修复..."
    apt install --reinstall apt -y 2>/dev/null || true
    apt update -qq
}

# 保护关键包（强化网络组件保护）
PROTECTED="sudo|openssh|systemd-networkd|systemd-resolved|systemd|network|netplan|networkd-dispatcher|network-manager|kernel|linux-|grub|libc6|init|base-|python3|dpkg|apt|debconf|cloud-init|ubuntu-server|ssh-import-id|ifupdown|isc-dhcp|resolvconf|dns"
REMOVE_PKGS=(htop tree nano vim neovim tmux screen git curl wget rsync p7zip-full unrar 
             ffmpeg nodejs npm python3-pip docker.io docker-ce docker-compose containerd.io 
             nginx apache2 mysql-server mariadb-server postgresql redis-server mongodb
             php php-fpm zsh fish neofetch btop nload iftop glances speedtest-cli 
             build-essential make cmake gcc g++ snap snapd flatpak)

# 安全删除包
for pkg in "${REMOVE_PKGS[@]}"; do
    [[ "$pkg" =~ $PROTECTED ]] && continue
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        log "尝试移除包: $pkg"
        if ! apt remove --purge -y "$pkg" -qq 2>/dev/null; then
            log "包 $pkg 删除失败，跳过"
            continue
        fi
    fi
done

# 设置基础包（强化网络组件）
if command -v ubuntu-minimal >/dev/null 2>&1; then
    BASE="ubuntu-minimal ubuntu-standard"
else
    BASE="base-files base-passwd bash coreutils apt"
fi
BASE="$BASE sudo openssh-server systemd-resolved systemd-networkd netplan.io network-manager networkd-dispatcher"

# 确保网络服务正常
log "检查网络服务..."
for service in systemd-networkd systemd-resolved; do
    if ! systemctl is-active "$service" >/dev/null 2>&1; then
        log "重启网络服务: $service"
        systemctl restart "$service" 2>/dev/null || true
    fi
done

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
