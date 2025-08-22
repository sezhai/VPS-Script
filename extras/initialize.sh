#!/bin/bash

# 系统清理脚本 - 精简版
# 适用于 Debian/Ubuntu 系统
# 警告：此脚本会直接删除文件，无备份功能！

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 确认操作
confirm_operation() {
    echo -e "${RED}警告: 此操作将永久删除所有后装应用和配置！${NC}"
    echo "清理内容："
    echo "  - 重置apt包到基础状态"
    echo "  - 删除 /usr/local/bin 中的程序"
    echo "  - 删除 /opt 中的软件"
    echo "  - 删除自定义systemd服务"
    echo "  - 删除用户本地安装的程序"
    echo
    read -p "确定继续？(输入 'YES' 确认): " confirmation
    if [[ "$confirmation" != "YES" ]]; then
        log_info "操作已取消"
        exit 0
    fi
}

# 停止并删除自定义服务
cleanup_systemd() {
    log_info "清理systemd服务..."
    
    for service_file in /etc/systemd/system/*.service; do
        if [[ -f "$service_file" ]]; then
            service_name=$(basename "$service_file")
            # 跳过系统关键服务
            if [[ ! "$service_name" =~ ^(getty@|network|ssh|cron|rsyslog|systemd-) ]]; then
                log_info "停止并删除服务: $service_name"
                systemctl stop "$service_name" 2>/dev/null || true
                systemctl disable "$service_name" 2>/dev/null || true
                rm -f "$service_file"
            fi
        fi
    done
    
    # 清理服务目录
    rm -rf /etc/systemd/system/*.wants/ 2>/dev/null || true
    rm -rf /etc/systemd/system/*.requires/ 2>/dev/null || true
    systemctl daemon-reload
    
    log_success "systemd服务清理完成"
}

# 清理apt包
cleanup_apt() {
    log_info "重置apt包..."
    
    apt update
    
    # 获取基础包列表
    if command -v ubuntu-minimal &> /dev/null; then
        BASE_PACKAGES="ubuntu-minimal ubuntu-standard"
    else
        BASE_PACKAGES="base-files base-passwd bash coreutils apt"
    fi
    
    # 常见后装软件包列表
    REMOVE_PACKAGES=(
        "htop"
        "tree" 
        "nano"
        "vim"
        "neovim"
        "tmux"
        "screen"
        "git"
        "curl"
        "wget"
        "rsync"
        "p7zip-full"
        "unrar"
        "ffmpeg"
        "nodejs"
        "npm"
        "python3-pip"
        "docker.io"
        "docker-ce"
        "containerd.io"
        "nginx"
        "apache2"
        "mysql-server"
        "mariadb-server"
        "postgresql"
        "redis-server"
        "mongodb"
        "php"
        "php-fpm"
        "zsh"
        "fish"
        "neofetch"
        "screenfetch"
        "btop"
        "nload"
        "iftop"
        "iotop"
        "glances"
        "speedtest-cli"
        "build-essential"
        "make"
        "cmake"
        "gcc"
        "g++"
    )
    
    # 尝试删除这些包
    for pkg in "${REMOVE_PACKAGES[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            log_info "移除包: $pkg"
            apt remove --purge -y "$pkg" 2>/dev/null || true
        fi
    done
    
    # 标记所有包为自动安装
    dpkg --get-selections | grep -v deinstall | awk '{print $1}' | xargs apt-mark auto 2>/dev/null || true
    
    # 重新标记基础包
    apt-mark manual $BASE_PACKAGES 2>/dev/null || true
    
    # 移除孤立包
    apt autoremove --purge -y
    apt autoclean
    apt clean
    
    log_success "apt包清理完成"
}

# 清理/usr/local/bin
cleanup_usr_local_bin() {
    log_info "清理 /usr/local/bin..."
    
    if [[ -d "/usr/local/bin" ]]; then
        # 清理常见手动安装的工具
        MANUAL_TOOLS=(
            "tree"
            "htop" 
            "btop"
            "gotop"
            "nano"
            "vim"
            "neovim"
            "nvim"
            "tmux"
            "screen"
            "git"
            "curl"
            "wget"
            "rsync"
            "7z"
            "unrar"
            "ffmpeg"
            "youtube-dl"
            "yt-dlp"
            "node"
            "npm"
            "yarn"
            "go"
            "python3"
            "pip"
            "pip3"
            "docker"
            "docker-compose"
            "kubectl"
            "helm"
            "terraform"
        )
        
        for tool in "${MANUAL_TOOLS[@]}"; do
            if [[ -f "/usr/local/bin/$tool" ]]; then
                log_info "删除手动安装的 $tool"
                rm -f "/usr/local/bin/$tool"
            fi
        done
        
        # 清理其他非系统文件
        find /usr/local/bin -type f -not -name ".*" -delete 2>/dev/null || true
        log_success "/usr/local/bin 清理完成"
    fi
}

# 清理/opt目录
cleanup_opt() {
    log_info "清理 /opt..."
    
    if [[ -d "/opt" ]]; then
        rm -rf /opt/* 2>/dev/null || true
        log_success "/opt 清理完成"
    fi
}

# 清理用户程序
cleanup_user_apps() {
    log_info "清理用户程序..."
    
    for user_home in /home/*/; do
        if [[ -d "$user_home" ]]; then
            # 清理用户本地程序
            rm -rf "$user_home/.local/bin"/* 2>/dev/null || true
            
            # 清理桌面应用
            find "$user_home/.local/share/applications" -name "*.desktop" -delete 2>/dev/null || true
        fi
    done
    
    log_success "用户程序清理完成"
}

# 清理常见后装应用
cleanup_common_apps() {
    log_info "清理常见后装应用..."
    
    # Xray 相关清理
    log_info "清理 Xray..."
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    rm -rf /usr/local/bin/xray
    rm -rf /usr/local/etc/xray
    rm -rf /etc/xray
    rm -rf /var/log/xray
    rm -rf /etc/systemd/system/xray.service
    
    # V2Ray 相关清理
    log_info "清理 V2Ray..."
    systemctl stop v2ray 2>/dev/null || true
    systemctl disable v2ray 2>/dev/null || true
    rm -rf /usr/local/bin/v2ray
    rm -rf /usr/local/bin/v2ctl
    rm -rf /usr/local/etc/v2ray
    rm -rf /etc/v2ray
    rm -rf /var/log/v2ray
    rm -rf /etc/systemd/system/v2ray.service
    
    # Sing-box 相关清理
    log_info "清理 Sing-box..."
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    rm -rf /usr/local/bin/sing-box
    rm -rf /usr/bin/sing-box
    rm -rf /etc/sing-box
    rm -rf /usr/local/etc/sing-box
    rm -rf /var/log/sing-box
    rm -rf /etc/systemd/system/sing-box.service
    pkill -f sing-box 2>/dev/null || true
    
    # Hysteria2 相关清理
    log_info "清理 Hysteria2..."
    systemctl stop hysteria 2>/dev/null || true
    systemctl stop hysteria2 2>/dev/null || true
    systemctl stop hy2 2>/dev/null || true
    systemctl disable hysteria 2>/dev/null || true
    systemctl disable hysteria2 2>/dev/null || true
    systemctl disable hy2 2>/dev/null || true
    rm -rf /usr/local/bin/hysteria
    rm -rf /usr/local/bin/hysteria2
    rm -rf /usr/local/bin/hy2
    rm -rf /usr/bin/hysteria
    rm -rf /usr/bin/hysteria2
    rm -rf /usr/bin/hy2
    rm -rf /etc/hysteria
    rm -rf /etc/hysteria2
    rm -rf /usr/local/etc/hysteria
    rm -rf /usr/local/etc/hysteria2
    rm -rf /var/log/hysteria
    rm -rf /var/log/hysteria2
    rm -rf /etc/systemd/system/hysteria.service
    rm -rf /etc/systemd/system/hysteria2.service
    rm -rf /etc/systemd/system/hy2.service
    pkill -f hysteria 2>/dev/null || true
    pkill -f hy2 2>/dev/null || true
    
    # Clash 相关清理
    log_info "清理 Clash..."
    systemctl stop clash 2>/dev/null || true
    systemctl stop clash-meta 2>/dev/null || true
    systemctl disable clash 2>/dev/null || true
    systemctl disable clash-meta 2>/dev/null || true
    rm -rf /usr/local/bin/clash
    rm -rf /usr/local/bin/clash-meta
    rm -rf /usr/bin/clash
    rm -rf /usr/bin/clash-meta
    rm -rf /etc/clash
    rm -rf /usr/local/etc/clash
    rm -rf /var/log/clash
    rm -rf /etc/systemd/system/clash.service
    rm -rf /etc/systemd/system/clash-meta.service
    pkill -f clash 2>/dev/null || true
    
    # Tuic 相关清理
    log_info "清理 Tuic..."
    systemctl stop tuic 2>/dev/null || true
    systemctl disable tuic 2>/dev/null || true
    rm -rf /usr/local/bin/tuic
    rm -rf /usr/local/bin/tuic-client
    rm -rf /usr/local/bin/tuic-server
    rm -rf /usr/bin/tuic*
    rm -rf /etc/tuic
    rm -rf /etc/systemd/system/tuic.service
    pkill -f tuic 2>/dev/null || true
    
    # 哪吒监控相关清理
    log_info "清理哪吒监控..."
    systemctl stop nezha-agent 2>/dev/null || true
    systemctl stop nezha-dashboard 2>/dev/null || true
    systemctl disable nezha-agent 2>/dev/null || true
    systemctl disable nezha-dashboard 2>/dev/null || true
    rm -rf /opt/nezha
    rm -rf /etc/systemd/system/nezha-agent.service
    rm -rf /etc/systemd/system/nezha-dashboard.service
    pkill -f nezha 2>/dev/null || true
    
    # 1Panel 面板清理
    log_info "清理 1Panel..."
    systemctl stop 1panel 2>/dev/null || true
    systemctl disable 1panel 2>/dev/null || true
    rm -rf /usr/local/bin/1panel
    rm -rf /opt/1panel
    rm -rf /etc/1panel
    rm -rf /var/lib/1panel
    rm -rf /etc/systemd/system/1panel.service
    pkill -f 1panel 2>/dev/null || true
    
    # 宝塔面板清理
    log_info "清理宝塔面板..."
    systemctl stop bt 2>/dev/null || true
    systemctl disable bt 2>/dev/null || true
    rm -rf /www/server/panel
    rm -rf /www/server/bt-tasks
    rm -rf /etc/systemd/system/bt.service
    pkill -f bt.py 2>/dev/null || true
    
    # aaPanel 清理
    log_info "清理 aaPanel..."
    systemctl stop aapanel 2>/dev/null || true
    systemctl disable aapanel 2>/dev/null || true
    rm -rf /www/server/panel
    rm -rf /etc/systemd/system/aapanel.service
    
    # Portainer 清理
    log_info "清理 Portainer..."
    systemctl stop portainer 2>/dev/null || true
    systemctl disable portainer 2>/dev/null || true
    rm -rf /opt/portainer
    rm -rf /var/lib/portainer
    rm -rf /etc/systemd/system/portainer.service
    
    # Nginx (如果是手动编译安装)
    log_info "清理手动安装的 Nginx..."
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    rm -rf /usr/local/nginx
    rm -rf /etc/nginx
    rm -rf /var/log/nginx
    rm -rf /etc/systemd/system/nginx.service
    
    # Caddy
    log_info "清理 Caddy..."
    systemctl stop caddy 2>/dev/null || true
    systemctl disable caddy 2>/dev/null || true
    rm -rf /usr/bin/caddy
    rm -rf /etc/caddy
    rm -rf /var/lib/caddy
    rm -rf /etc/systemd/system/caddy.service
    
    # Frp (内网穿透)
    log_info "清理 FRP..."
    systemctl stop frps frpc 2>/dev/null || true
    systemctl disable frps frpc 2>/dev/null || true
    rm -rf /opt/frp
    rm -rf /etc/frp
    rm -rf /etc/systemd/system/frp*.service
    
    # Docker 相关
    log_info "清理 Docker..."
    systemctl stop docker containerd 2>/dev/null || true
    systemctl disable docker containerd 2>/dev/null || true
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    rm -rf /etc/docker
    
    # 其他常见应用和工具
    COMMON_APPS=(
        "aria2"
        "filebrowser"
        "rclone"
        "restic"
        "syncthing"
        "transmission"
        "qbittorrent"
        "shadowsocks"
        "ss-server"
        "ss-local"
        "trojan"
        "trojan-go"
        "naive"
        "brook"
        "gost"
        "kcptun"
        "htop"
        "btop"
        "gotop"
        "nload"
        "iftop"
        "iotop"
        "glances"
        "speedtest-cli"
        "neofetch"
        "screenfetch"
    )
    
    for app in "${COMMON_APPS[@]}"; do
        log_info "清理 $app..."
        systemctl stop "$app" 2>/dev/null || true
        systemctl disable "$app" 2>/dev/null || true
        rm -rf "/etc/systemd/system/$app.service"
        pkill -f "$app" 2>/dev/null || true
    done
    
    log_success "常见后装应用清理完成"
}

# 清理第三方数据
cleanup_third_party() {
    log_info "清理第三方数据..."
    
    # 常见第三方软件数据目录
    DIRS_TO_CLEAN=(
        "/var/lib/docker"
        "/var/lib/containerd"
        "/var/lib/snapd"
        "/var/lib/flatpak"
    )
    
    for dir in "${DIRS_TO_CLEAN[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "删除 $dir"
            rm -rf "$dir"
        fi
    done
    
    # 清理第三方应用文件
    find /usr/share/applications -name "*.desktop" -not -path "*/dpkg/*" -delete 2>/dev/null || true
    
    log_success "第三方数据清理完成"
}

# 清理缓存
cleanup_cache() {
    log_info "清理缓存..."
    
    # 系统缓存
    rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
    
    # 用户缓存
    for user_home in /home/*/; do
        if [[ -d "$user_home" ]]; then
            rm -rf "$user_home/.cache"/* 2>/dev/null || true
        fi
    done
    
    log_success "缓存清理完成"
}

# 更新系统
update_system() {
    log_info "更新系统组件..."
    
    update-initramfs -u 2>/dev/null || true
    
    if command -v update-grub &> /dev/null; then
        update-grub 2>/dev/null || true
    fi
    
    log_success "系统组件更新完成"
}

# 主函数
main() {
    echo "=================================="
    echo "    系统清理脚本 - 精简版        "
    echo "=================================="
    echo
    
    check_root
    confirm_operation
    
    echo "开始清理..."
    cleanup_systemd
    cleanup_common_apps
    cleanup_opt
    cleanup_usr_local_bin
    cleanup_user_apps
    cleanup_third_party
    cleanup_apt
    cleanup_cache
    update_system
    
    echo
    echo "=================================="
    log_success "系统清理完成！"
    echo "建议重启系统: sudo reboot"
    echo "=================================="
}

# 执行主函数
main "$@"
