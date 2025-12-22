#!/bin/bash
# VPS 管理脚本

# =============================================================================
# 全局配置与变量
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[1;34m'
CYAN='\033[1;96m'
PLAIN='\033[0m'

# =============================================================================
# 通用工具函数
# =============================================================================

# 打印带颜色的信息
log_info() { echo -e "${BLUE}[INFO]${PLAIN} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${PLAIN} $1"; }
log_error() { echo -e "${RED}[ERROR]${PLAIN} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${PLAIN} $1"; }

# 按任意键继续
press_any_key() {
    echo
    read -n 1 -s -r -p "按任意键返回..."
    echo
}

# 打印菜单标题
print_header() {
    clear
    echo "========================================="
    echo -e "               ${CYAN}$1${PLAIN}"
    echo "========================================="
}

# 检查命令执行状态
check_status() {
    if [ $? -eq 0 ]; then
        log_success "$1 成功！"
    else
        log_error "$1 失败！$2"
    fi
}

# 获取公网IP (IPv4优先)
get_public_ip() {
    local ipv4=$(curl -s -4 --connect-timeout 5 https://api.ipify.org 2>/dev/null)
    if [[ -z "$ipv4" ]]; then
        ipv4=$(curl -s -4 --connect-timeout 5 https://icanhazip.com 2>/dev/null | tr -d '\n')
    fi
    if [[ -n "$ipv4" && "$ipv4" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ipv4"
        return
    fi
    
    local ipv6=$(curl -s -6 --connect-timeout 5 https://api6.ipify.org 2>/dev/null)
    if [[ -z "$ipv6" ]]; then
        ipv6=$(curl -s -6 --connect-timeout 5 https://icanhazip.com 2>/dev/null | tr -d '\n')
    fi
    if [[ -n "$ipv6" ]]; then
        echo "$ipv6"
        return
    fi
    echo "127.0.0.1"
}

# 从证书文件提取域名
get_domain_from_cert() {
    local cert_file="$1"
    if [[ -f "$cert_file" ]]; then
        openssl x509 -in "$cert_file" -text -noout | grep -Po "DNS:[^,]*" | head -n 1 | sed 's/DNS://' || \
        openssl x509 -in "$cert_file" -text -noout | grep -Po "CN=[^ ]*" | sed 's/CN=//'
    fi
}

# =============================================================================
# 1. 系统信息模块
# =============================================================================

view_vps_info() {
    clear
    print_header "VPS 系统信息"
    
    echo -e "${BLUE}主机名:${PLAIN} ${GREEN}$(hostname)${PLAIN}"
    echo -e "${BLUE}系统版本:${PLAIN} ${GREEN}$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)${PLAIN}"
    echo -e "${BLUE}Linux版本:${PLAIN} ${GREEN}$(uname -r)${PLAIN}"
    echo "-------------"
    echo -e "${BLUE}CPU架构:${PLAIN} ${GREEN}$(uname -m)${PLAIN}"
    
    local cpu_model=$(grep -m1 'model name' /proc/cpuinfo | awk -F: '{print $2}' | sed 's/^[ \t]*//')
    if [ -z "$cpu_model" ]; then
        cpu_model=$(lscpu | grep 'Model name' | sed 's/Model name:[ \t]*//' | head -n 1)
    fi
    echo -e "${BLUE}CPU型号:${PLAIN} ${GREEN}${cpu_model}${PLAIN}"
    
    echo -e "${BLUE}CPU核心数:${PLAIN} ${GREEN}$(nproc)${PLAIN}"
    
    local cpu_mhz=$(grep -m1 'cpu MHz' /proc/cpuinfo | awk -F: '{print $2}' | sed 's/^[ \t]*//')
    if [ -z "$cpu_mhz" ]; then
         cpu_mhz=$(lscpu | grep 'CPU MHz' | awk -F: '{print $2}' | xargs)
    fi
    if [ -z "$cpu_mhz" ]; then cpu_mhz="未知"; fi
    echo -e "${BLUE}CPU频率:${PLAIN} ${GREEN}${cpu_mhz} MHz${PLAIN}"
    
    echo "-------------"
    echo -e "${BLUE}CPU占用:${PLAIN} ${GREEN}$(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')%${PLAIN}"
    echo -e "${BLUE}系统负载:${PLAIN} ${GREEN}$(awk '{print $1, $2, $3}' /proc/loadavg)${PLAIN}"
    
    local mem_info=$(free -m | awk '/Mem:/ {total=$2; used=$3; if (total > 0) printf "%.2f/%.2f MB (%.2f%%)", used, total, used*100/total; else print "数据不可用"}')
    echo -e "${BLUE}物理内存:${PLAIN} ${GREEN}$mem_info ${PLAIN}"
    
    local swap_info=$(free -m | awk '/Swap:/ {total=$2; used=$3; if (total > 0) printf "%.0fMB/%.0fMB (%.0f%%)", used, total, used*100/total; else print "数据不可用" }')
    echo -e "${BLUE}虚拟内存:${PLAIN} ${GREEN}$swap_info${PLAIN}"
    
    echo -e "${BLUE}硬盘占用:${PLAIN} ${GREEN}$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}') ${PLAIN}"
    
    echo "-------------"
    local NET_INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}' | head -n 1)
    if [ -n "$NET_INTERFACE" ]; then
        local RX_BYTES=$(cat /sys/class/net/$NET_INTERFACE/statistics/rx_bytes)
        local TX_BYTES=$(cat /sys/class/net/$NET_INTERFACE/statistics/tx_bytes)
        local RX_MB=$(awk "BEGIN {printf \"%.2f\", $RX_BYTES / 1024 / 1024}")
        local TX_MB=$(awk "BEGIN {printf \"%.2f\", $TX_BYTES / 1024 / 1024}")
        echo -e "${BLUE}网络接口:${PLAIN} ${GREEN}$NET_INTERFACE${PLAIN}"
        echo -e "${BLUE}总接收:${PLAIN} ${GREEN}${RX_MB} MB${PLAIN}"
        echo -e "${BLUE}总发送:${PLAIN} ${GREEN}${TX_MB} MB${PLAIN}"
    else
        echo -e "${RED}未检测到有效的网络接口！${PLAIN}"
    fi
    echo "-------------"
    
    if [ -f /proc/sys/net/ipv4/tcp_congestion_control ]; then
        echo -e "${BLUE}网络算法:${PLAIN} ${GREEN}$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')${PLAIN}"
    else
        echo -e "${BLUE}网络算法:${PLAIN} ${RED}IPv4 未启用或不支持。${PLAIN}"
    fi
    echo "-------------"
    
    echo -e "${BLUE}运营商:${PLAIN} ${GREEN}$(curl -s ipinfo.io/org | sed 's/^ *//;s/ *$//')${PLAIN}"
    echo -e "${BLUE}IPv4地址:${PLAIN} ${GREEN}$(curl -s ipv4.icanhazip.com)${PLAIN}"
    echo -e "${BLUE}IPv6地址:${PLAIN} ${GREEN}$(ip -6 addr show scope global | awk '/inet6/ && !/temporary|tentative/ {print $2}' | cut -d'/' -f1 | head -n1 | ( grep . || echo "未检测到IPv6地址" ))${PLAIN}"
    echo -e "${BLUE}DNS地址:${PLAIN} ${GREEN}$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | xargs | sed 's/ /, /g')${PLAIN}"
    echo -e "${BLUE}地理位置:${PLAIN} ${GREEN}$(curl -s ipinfo.io/city), $(curl -s ipinfo.io/country)${PLAIN}"
    echo -e "${BLUE}系统时间:${PLAIN} ${GREEN}$(timedatectl | grep 'Local time' | awk '{print $3, $4, $5}')${PLAIN}"
    echo "-------------"
    echo -e "${BLUE}运行时长:${PLAIN} ${GREEN}$(uptime -p | sed 's/up //')${PLAIN}"
    echo "-------------"
    
    press_any_key
}

# =============================================================================
# 2. 系统优化模块
# =============================================================================

calibrate_time() {
    echo -e "\n[校准时间]"
    sudo timedatectl set-timezone Asia/Shanghai
    sudo timedatectl set-ntp true
    log_success "时间校准完成，当前时区为 Asia/Shanghai。"
    press_any_key
}

update_system() {
    echo -e "\n[更新系统]"
    if ! sudo apt update -y && ! sudo apt full-upgrade -y; then
        log_error "系统更新失败！请检查网络连接或源列表。"
    else
        sudo apt autoremove -y && sudo apt autoclean -y
        log_success "系统更新完成！"
    fi
    press_any_key
}

clean_system() {
    echo -e "\n[清理系统]"
    sudo apt autoremove --purge -y
    sudo apt clean -y && sudo apt autoclean -y
    sudo journalctl --rotate && sudo journalctl --vacuum-time=10m
    sudo journalctl --vacuum-size=50M
    log_success "系统清理完成！"
    press_any_key
}

enable_bbr() {
    echo -e "\n[开启BBR]"
    if sysctl net.ipv4.tcp_congestion_control | grep -q 'bbr'; then
        log_success "BBR已开启！"
    else
        echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control = bbr" | sudo tee -a /etc/sysctl.conf
        if sudo sysctl -p; then
            log_success "BBR已开启！"
        else
            log_error "BBR 开启失败！"
        fi
    fi
    press_any_key
}

root_login() {
    while true; do
        print_header "ROOT登录"
        echo "1) 设置密码"
        echo "2) 修改配置"
        echo "3) 重启服务"
        echo "========================================="
        read -p "请输入数字 [1-3] 选择 (默认回车退出)：" root_choice
        case "$root_choice" in
            1)
                sudo passwd root
                press_any_key
                ;;
            2)
                sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
                sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
                log_success "配置修改成功！"
                press_any_key
                ;;
            3)
                sudo systemctl restart sshd.service
                check_status "ROOT登录开启"
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项。" ;;
        esac
    done
}

user_sysinit() {
    set -e
    read -p "$(echo -e '\033[0;31m输入y继续（默认回车退出）:\033[0m ') " confirm
    [[ "$confirm" != "y" ]] && return 0

    echo "开始系统清理..."
    
    log_info "清理后装应用文件..."
    local CLEANUP_PATHS=(
        "/usr/local/bin/xray" "/usr/local/bin/v2ray" "/usr/local/bin/v2ctl"
        "/usr/local/bin/sing-box" "/usr/local/bin/hysteria" "/usr/local/bin/hysteria2"
        "/usr/local/bin/hy2" "/usr/local/bin/clash" "/usr/local/bin/clash-meta"
        "/usr/local/bin/trojan" "/usr/local/bin/trojan-go" "/usr/local/bin/tuic"
        "/usr/bin/caddy"
        "/usr/local/bin/1panel" "/opt/1panel" "/opt/nezha" "/opt/ql"
        "/opt/portainer" "/opt/filebrowser" "/opt/frp"
        "/www/server/panel" "/www/server/bt-tasks"
        "/etc/aria2" "/etc/xray" "/etc/v2ray" "/etc/sing-box" "/etc/hysteria"
        "/etc/hysteria2" "/etc/clash" "/etc/trojan" "/etc/caddy" "/etc/frp"
        "/etc/1panel" "/etc/nezha" "/usr/local/etc/xray" "/usr/local/etc/v2ray"
        "/usr/local/etc/sing-box" "/usr/local/etc/clash"
        "/var/lib/1panel" "/var/log/xray" "/var/log/v2ray" "/var/log/sing-box"
        "/var/log/hysteria" "/var/log/nginx"
    )
    for path in "${CLEANUP_PATHS[@]}"; do
        if [[ -e "$path" ]]; then
            rm -rf "$path" 2>/dev/null && log_info "删除: $path"
        fi
    done

    log_info "清理后装systemd服务..."
    local CLEANUP_SERVICES=(
        "xray" "v2ray" "sing-box" "hysteria" "hysteria2" "hy2"
        "clash" "trojan" "caddy" "frps" "frpc" "1panel"
        "nezha-agent" "nezha-dashboard" "aria2" "filebrowser"
        "portainer" "docker" "containerd"
    )
    for service in "${CLEANUP_SERVICES[@]}"; do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
        rm -f "/etc/systemd/system/${service}.service"
        rm -f "/etc/systemd/system/${service}d.service"
        rm -f "/etc/systemd/system/${service}-agent.service"
        rm -f "/etc/systemd/system/${service}-dashboard.service"
    done
    systemctl daemon-reload 2>/dev/null || true

    log_info "终止后装应用进程..."
    local KILL_PATTERNS=(
        "xray" "v2ray" "sing-box" "hysteria" "clash" "trojan"
        "caddy" "frps" "frpc" "1panel" "nezha" "aria2"
        "filebrowser" "portainer" "docker" "containerd"
    )
    for pattern in "${KILL_PATTERNS[@]}"; do
        pkill -f "$pattern" 2>/dev/null || true
    done

    log_info "删除后装APT包..."
    local REMOVE_PKGS=("docker.io" "docker-ce" "docker-compose" "containerd.io" "docker-compose-plugin")
    for pkg in "${REMOVE_PKGS[@]}"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            log_info "删除APT包: $pkg"
            apt remove --purge -y "$pkg" -qq 2>/dev/null || true
        fi
    done

    log_info "清理用户目录..."
    for home in /home/*/; do
        [[ -d "$home" ]] || continue
        rm -rf "${home}.config/1panel" "${home}.config/clash" "${home}.config/v2ray" \
               "${home}.xray" "${home}.v2ray" 2>/dev/null || true
    done

    log_info "清理缓存..."
    rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
    apt autoclean apt clean 2>/dev/null || true

    log_info "验证系统完整性..."
    dpkg --configure -a --force-confold 2>/dev/null || true
    apt update -qq 2>/dev/null || {
        log_info "尝试修复APT..."
        apt install -f -y -qq 2>/dev/null || true
        apt update -qq 2>/dev/null || true
    }

    for service in systemd-resolved systemd-networkd networking; do
        systemctl is-enabled "$service" >/dev/null 2>&1 && \
            systemctl restart "$service" 2>/dev/null || true
    done

    log_success "系统初始化完成！"
    read -p "$(echo -e '\033[0;31m输入y重启系统（默认回车退出）:\033[0m ') " reboot_choice
    [[ "$reboot_choice" == "y" ]] && sudo reboot
    press_any_key
}

display_system_optimization_menu() {
    while true; do
        print_header "系统优化"
        echo "1) 校准时间"
        echo "2) 更新系统"
        echo "3) 清理系统"
        echo "4) 开启BBR"
        echo "5) ROOT登录"
        echo "6) 系统初始化"
        echo "========================================="
        read -p "请输入数字 [1-6] 选择 (默认回车退出)：" root_choice
        case "$root_choice" in
            1) calibrate_time ;;
            2) update_system ;;
            3) clean_system ;;
            4) enable_bbr ;;
            5) root_login ;;
            6) user_sysinit ;;
            "") return ;;
            *) log_error "无效选项，请重新输入。" ;;
        esac
    done
}

# =============================================================================
# 3. 常用工具模块
# =============================================================================

common_tools() {
    while true; do
        print_header "常用工具"
        echo "1) 查找文件"
        echo "2) 赋予权限"
        echo "3) 删除文件"
        echo "4) 查看进程"
        echo "5) 关闭进程"
        echo "6) 查看端口"
        echo "7) 开放端口"
        echo "8) 网络测速"
        echo "========================================="
        read -p "请输入数字 [1-8] 选择 (默认回车退出)：" root_choice
        case "$root_choice" in
            1)
                read -p "请输入要查找的文件名: " filename
                if [[ -z "$filename" ]]; then
                    log_error "文件名不能为空。"
                else
                    find / -type f -name "*$filename*" 2>/dev/null
                    [[ $? -ne 0 ]] && log_error "未找到匹配的文件。"
                fi
                press_any_key
                ;;
            2)
                read -p "请输入文件路径: " file_path
                if [ ! -e "$file_path" ]; then
                    log_error "错误: 文件或目录 '$file_path' 不存在。"
                else
                    chmod 755 "$file_path"
                    if [ $? -eq 0 ]; then
                        log_success "'$file_path' 权限已设置为 755！"
                    else
                        log_error "错误: 设置权限失败。"
                    fi
                fi
                press_any_key
                ;;
            3)
                while true; do
                    read -p "请输入要删除的文件或目录名（默认回车退出）: " filename
                    [[ -z "$filename" ]] && break
                    files=($(find / -type f -iname "*$filename*" -o -type d -iname "*$filename*" 2>/dev/null))
                    if [[ ${#files[@]} -eq 0 ]]; then
                        log_error "未找到匹配的文件或目录。"
                        continue
                    fi
                    echo "找到以下文件或目录:"
                    for i in "${!files[@]}"; do
                        echo "$((i+1)). ${files[$i]}"
                    done
                    read -p "请输入要删除的编号（多选空格分隔）: " choices
                    [[ -z "$choices" ]] && { echo "取消操作。"; continue; }
                    
                    IFS=' ' read -r -a choice_array <<< "$choices"
                    for choice in "${choice_array[@]}"; do
                        if [[ "$choice" -ge 1 && "$choice" -le ${#files[@]} ]]; then
                            file="${files[$((choice-1))]}"
                            read -p "确定要删除 $file 吗？ (y/n): " confirm
                            if [[ "$confirm" == "y" ]]; then
                                rm -rf "$file"
                                log_success "已删除: $file"
                            else
                                echo "跳过: $file"
                            fi
                        else
                            log_error "无效选择: $choice"
                        fi
                    done
                done
                press_any_key
                ;;
            4)
                ps aux
                press_any_key
                ;;
            5)
                while true; do
                    read -p "请输入要关闭的进程 PID: " pid
                    if [[ "$pid" =~ ^[0-9]+$ ]]; then
                        if kill "$pid"; then
                            log_success "进程 $pid 已成功关闭！"
                        else
                            echo -e "${RED}无法正常关闭，是否强制关闭 (SIGKILL)？ (y/n)${PLAIN}"
                            read -p "请选择: " choice
                            if [[ "$choice" == "y" ]]; then
                                kill -9 "$pid" && log_success "进程 $pid 已强制关闭！" || log_error "强制关闭失败。"
                            else
                                echo "取消强制关闭"
                            fi
                        fi
                        break
                    else
                        log_error "无效的 PID。"
                    fi
                done
                press_any_key
                ;;
            6)
                echo -e "端口     类型    程序名               PID"
                if command -v ss &>/dev/null; then
                    ss -tulnp | awk 'NR>1 {
                        split($5, a, ":"); split($7, b, ",");
                        gsub(/[()]/, "", b[1]); gsub(/pid=/, "", b[2]); gsub(/users:/, "", b[1]); gsub(/"/, "", b[1]);
                        if (a[2] != "" && a[2] != "*") printf "%-8s %-7s %-20s %-6s\n", a[2], $1, b[1], b[2];
                    }'
                else
                    netstat -tulnp | awk 'NR>2 {
                        split($4, a, ":"); split($7, b, "/");
                        gsub(/[()]/, "", b[1]); gsub(/pid=/, "", b[2]); gsub(/users:/, "", b[1]); gsub(/"/, "", b[1]);
                        if (a[2] != "" && a[2] != "*") printf "%-8s %-7s %-20s %-6s\n", a[2], $1, b[1], b[2];
                    }'
                fi
                press_any_key
                ;;
            7)
                while true; do
                    echo "1) TCP  2) UDP"
                    read -p "请输入协议 [1-2]: " p_choice
                    case "$p_choice" in
                        1) protocol="tcp" ;; 2) protocol="udp" ;; *) log_error "无效选择"; break ;;
                    esac
                    read -p "请输入端口号: " port
                    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                        log_error "无效端口号"
                        break
                    fi
                    sudo iptables -A INPUT -p $protocol --dport $port -j ACCEPT
                    check_status "端口 $port ($protocol) 开放"
                    break
                done
                press_any_key
                ;;
            8)
                if ! command -v speedtest-cli >/dev/null 2>&1; then
                    echo "安装 speedtest-cli..."
                    sudo apt update && sudo apt install -y speedtest-cli
                fi
                echo "开始测速..."
                speedtest-cli
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项。" ;;
        esac
    done
}

# =============================================================================
# 4. 常用软件包模块
# =============================================================================

# 通用软件包管理辅助函数
manage_package_menu() {
    local pkg_name=$1
    local pkg_display=$2
    local install_cmd=${3:-"sudo apt update && sudo apt install -y $pkg_name"}
    local remove_cmd=${4:-"sudo apt remove -y $pkg_name"}

    echo "1) 安装"
    echo "2) 卸载"
    read -p "请选择操作 (默认回车退出)：" action
    case "$action" in
        1)
            eval "$install_cmd"
            check_status "$pkg_display 安装"
            ;;
        2)
            eval "$remove_cmd"
            check_status "$pkg_display 卸载"
            ;;
        "") ;;
        *) log_error "无效选项" ;;
    esac
    press_any_key
}

install_package() {
    while true; do
        print_header "常用软件包"
        echo "1) apt 更新"
        echo "2) sudo"
        echo "3) wget"
        echo "4) nano"
        echo "5) vim"
        echo "6) zip"
        echo "7) git"
        echo "8) htop"
        echo "9) docker"
        echo "========================================="
        read -p "请输入数字 [1-9] 选择 (默认回车退出)：" opt_choice
        case "$opt_choice" in
            1)
                sudo apt update
                check_status "apt 更新"
                press_any_key
                ;;
            2) manage_package_menu "sudo" "sudo" ;;
            3) manage_package_menu "wget" "wget" ;;
            4) manage_package_menu "nano" "nano" ;;
            5) manage_package_menu "vim" "vim" ;;
            6) manage_package_menu "zip" "zip" ;;
            7) manage_package_menu "git" "git" ;;
            8) manage_package_menu "htop" "htop" ;;
            9)
                manage_package_menu "docker" "docker" \
                    "curl -fsSL https://get.docker.com | bash" \
                    "sudo systemctl stop docker docker.socket && sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras && sudo apt-get autoremove -y && sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker"
                ;;
            "") return ;;
            *) log_error "无效选项" ;;
        esac
    done
}

# =============================================================================
# 5. 证书管理模块
# =============================================================================

apply_certificate() {
    while true; do
        print_header "申请证书"
        echo "1) 安装脚本 (acme.sh)"
        echo "2) 申请证书"
        echo "3) 更换服务器 (Let's Encrypt)"
        echo "4) 安装证书"
        echo "5) 卸载脚本"
        echo "========================================="
        read -p "请输入数字 [1-5] 选择 (默认回车退出)：" cert_choice
        case "$cert_choice" in
            1)
                read -p "请输入邮箱地址: " email
                sudo apt update
                command -v crontab &> /dev/null || sudo apt install -y cron
                command -v socat &> /dev/null || sudo apt install -y socat
                curl https://get.acme.sh | sh -s email="$email"
                check_status "acme.sh 安装"
                press_any_key
                ;;
            2)
                read -p "请输入域名: " domain
                ~/.acme.sh/acme.sh --issue --standalone -d "$domain"
                check_status "证书申请"
                press_any_key
                ;;
            3)
                ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                check_status "切换至 Let's Encrypt"
                press_any_key
                ;;
            4)
                read -p "请输入域名: " domain
                read -p "请输入证书安装路径（默认: /path/to）: " install_path
                install_path=${install_path:-/path/to}
                mkdir -p "$install_path" && \
                ~/.acme.sh/acme.sh --installcert -d "$domain" \
                    --key-file "$install_path/key.key" --fullchain-file "$install_path/certificate.crt" && \
                sudo chmod 644 "$install_path/certificate.crt" "$install_path/key.key"
                check_status "证书安装"
                press_any_key
                ;;
            5)
                ~/.acme.sh/acme.sh --uninstall
                check_status "acme.sh 卸载"
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项" ;;
        esac
    done
}

# =============================================================================
# 6. Xray 安装模块
# =============================================================================

install_xray() {
    while true; do
        print_header "安装Xray"
        echo "1) VMESS-WS-TLS"
        echo "2) VLESS-TCP-REALITY"
        echo "3) 卸载服务"
        echo "========================================="
        read -p "请输入数字 [1-3] 选择 (默认回车退出)：" opt_choice
        case "$opt_choice" in
            1) install_xray_tls ;;
            2) install_xray_reality ;;
            3)
                bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
                check_status "Xray 卸载"
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项" ;;
        esac
    done
}

install_xray_tls() {
    while true; do
        print_header "VMESS-WS-TLS"
        echo "1) 安装升级"
        echo "2) 编辑配置"
        echo "3) 重启服务"
        echo "========================================="
        read -p "请输入数字 [1-3] 选择功能 (默认回车退出)：" xray_choice
        case "$xray_choice" in
            1)
                if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install && \
                   sudo curl -o /usr/local/etc/xray/config.json "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VMess-Websocket-TLS/config_server.jsonc"; then
                    log_success "Xray 安装升级完成！"
                    echo -e "UUID: ${BLUE}$(xray uuid)${PLAIN}"
                else
                    log_error "Xray 安装升级失败！"
                fi
                press_any_key
                ;;
            2)
                echo -e "${YELLOW}提示：将UUID填入配置文件中。若已执行成功默认设置的“安装证书”则证书路径无须修改。${PLAIN}"
                read -n 1 -s -r -p "按任意键继续..."
                command -v nano >/dev/null 2>&1 || sudo apt install -y nano
                sudo nano /usr/local/etc/xray/config.json
                press_any_key
                ;;
            3)
                CONFIG_PATH="/usr/local/etc/xray/config.json"
                sudo -H systemctl restart xray 2>/dev/null
                sleep 2
                if ! systemctl is-active --quiet xray; then
                    log_error "未能启动 xray 服务，请检查日志。"
                    systemctl status xray --no-pager
                else
                    log_success "xray已启动！"
                    extract_field() { grep -aPo "\"$1\":\s*$2" "$CONFIG_PATH" | head -n 1 | sed -E "s/\"$1\":\s*//;s/^\"//;s/\"$//"; }
                    extract_list_field() { grep -aPoz "\"$1\":\s*\[\s*\{[^}]*\}\s*\]" "$CONFIG_PATH" | grep -aPo "\"$2\":\s*\"[^\"]*\"" | head -n 1 | sed -E "s/\"$2\":\s*\"([^\"]*)\"/\1/"; }
                    
                    UUID=$(extract_list_field "clients" "id")
                    PORT=$(extract_field "port" "\d+")
                    WS_PATH=$(extract_field "path" "\"[^\"]*\"")
                    TLS=$(extract_field "security" "\"[^\"]*\"")
                    CERT_PATH=$(extract_list_field "certificates" "certificateFile")
                    
                    [[ -z "$CERT_PATH" ]] && { log_error "未能找到证书路径。"; break; }
                    
                    DOMAIN=$(get_domain_from_cert "$CERT_PATH")
                    SNI=${DOMAIN:-"your.domain.net"}
                    HOST=${DOMAIN:-"your.domain.net"}
                    ADDRESS=$(get_public_ip)
                    WS_PATH=${WS_PATH:-"/"}
                    TLS=${TLS:-"tls"}
                    PORT=${PORT:-"443"}
                    
                    vmess_uri="vmess://${UUID}@${ADDRESS}:${PORT}?encryption=none&security=${TLS}&sni=${SNI}&type=ws&host=${HOST}&path=${WS_PATH}#Xray"
                    echo "VLESS链接如下:"
                    echo -e "${BLUE}$vmess_uri${PLAIN}"
                fi
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项" ;;
        esac
    done
}

install_xray_reality() {
    while true; do
        print_header "VLESS-TCP-REALITY"
        echo "1) 安装升级"
        echo "2) 编辑配置"
        echo "3) 重启服务"
        echo "========================================="
        read -p "请输入数字 [1-3] 选择(默认回车退出)：" xray_choice
        case "$xray_choice" in
            1)
                if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install && \
                   sudo curl -o /usr/local/etc/xray/config.json "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-TCP-REALITY%20(without%20being%20stolen)/config_server.jsonc"; then
                    log_success "Xray 安装升级完成！"
                    echo -e "UUID: ${BLUE}$(xray uuid)${PLAIN}"
                    keys=$(xray x25519)
                    export PRIVATE_KEY=$(echo "$keys" | awk '/PrivateKey/ {print $2}')
                    export PUBLIC_KEY=$(echo "$keys" | awk '/Public key/  {print $3}')
                    
                    if [ -z "$PUBLIC_KEY" ]; then
                         export PUBLIC_KEY=$(echo "$keys" | awk '/Password/ {print $2}')
                    fi

                    echo -e "PrivateKey: ${BLUE}$PRIVATE_KEY${PLAIN}"
                    echo -e "ShortIds: ${BLUE}$(openssl rand -hex 8)${PLAIN}"
                else
                    log_error "Xray 安装升级失败！"
                fi
                press_any_key
                ;;
            2)
                echo -e "${YELLOW}提示：将UUID、目标网站及PrivateKey填入配置文件中，ShortIds非必须。${PLAIN}"
                read -n 1 -s -r -p "按任意键继续..."
                command -v nano >/dev/null 2>&1 || sudo apt install -y nano
                sudo nano /usr/local/etc/xray/config.json
                press_any_key
                ;;
            3)
                CONFIG_PATH="/usr/local/etc/xray/config.json"
                sudo -H systemctl restart xray 2>/dev/null
                sleep 2
                if ! systemctl is-active --quiet xray; then
                    log_error "未能启动 xray 服务，请检查日志。"
                    systemctl status xray --no-pager
                else
                    log_success "xray已启动！"
                    
                    extract_field() { grep -aPo "\"$1\":\s*$2" "$CONFIG_PATH" | head -n 1 | sed -E "s/\"$1\":\s*//;s/^\"//;s/\"$//"; }
                    extract_server_name() { grep -A 5 '"serverNames"' "$CONFIG_PATH" | grep -o '"[^"]*"' | head -n 2 | tail -n 1 | sed 's/"//g'; }
                    extract_list_field() {
                         local list_parent=$1; local list_field=$2
                         if [[ "$list_field" == "shortIds" || "$list_field" == "serverNames" ]]; then
                             local result=$(grep -aA 2 "\"$list_field\": \[" "$CONFIG_PATH" | awk 'NR==2{gsub(/^\s+|\s*\/\/.*$/,"");split($0,a,","); for (i in a) {gsub(/^["\s]+|["\s]+$/,"",a[i]);printf "%s ",a[i]}}')
                             echo "$result" | sed 's/[[:space:]]*$//;s/^ *//;s/^"//;s/"$//'
                         else
                             grep -aPoz "\"$list_parent\":\s*\[\s*\{[^}]*\}\s*\]" "$CONFIG_PATH" | grep -aPo "\"$list_field\":\s*\"[^\"]*\"" | head -n 1 | sed -E "s/\"$list_field\":\s*\"([^\"]*)\"/\1/"
                         fi
                    }
                    
                    UUID=$(extract_list_field "clients" "id")
                    PORT=$(extract_field "port" "\d+")
                    SERVER_NAME=$(extract_server_name)
                    SHORT_IDS=$(extract_list_field "realitySettings" "shortIds")
                    FLOW=$(extract_field "flow" "\"[^\"]*\"")
                    
                    EXISTING_PRIVATE_KEY=$(extract_field "privateKey" "\"[^\"]*\"")
                    
                    if [ -n "$PUBLIC_KEY" ]; then
                        PBK="$PUBLIC_KEY"
                    else
                        PBK=$(echo "$EXISTING_PRIVATE_KEY" | xray x25519 -i 2>/dev/null | grep -i "Public key" | awk '{print $NF}')
fi
                    
                    SNI=${SERVER_NAME:-"your.domain.net"}
                    ADDRESS=$(get_public_ip)
                    PORT=${PORT:-"443"}
                    SID=${SHORT_IDS:-""}
                    
                    if [ -z "$PBK" ]; then
                        echo -e "${YELLOW}警告: 无法从配置中提取私钥，也无缓存公钥，生成的链接可能缺少 pbk 参数。${PLAIN}"
                    fi

                    vless_uri="vless://${UUID}@${ADDRESS}:${PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${SNI}&fp=chrome&pbk=${PBK}&sid=${SID}&type=tcp&headerType=none#Xray-Reality"
                    
                    echo "VLESS链接如下："
                    echo -e "${BLUE}$vless_uri${PLAIN}"
                fi
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项" ;;
        esac
    done
}

# =============================================================================
# 7. Hysteria2 安装模块
# =============================================================================

install_hysteria2() {
    while true; do
        print_header "安装 Hysteria2"
        echo "1) 安装升级"
        echo "2) 编辑配置"
        echo "3) 重启服务"
        echo "4) 端口跳跃"
        echo "5) 卸载服务"
        echo "========================================="
        read -p "请输入数字 [1-5] 选择 (默认回车退出)：" h_choice
        case "$h_choice" in
            1)
                if bash <(curl -fsSL https://get.hy2.sh/) && sudo systemctl enable --now hysteria-server.service; then
                    sysctl -w net.core.rmem_max=16777216 || true
                    sysctl -w net.core.wmem_max=16777216 || true
                    log_success "hysteria2 安装升级完成！"
                else
                    log_error "hysteria2 安装升级失败！"
                fi
                press_any_key
                ;;
            2)
                echo -e "${YELLOW}提示：将域名填入配置文件中。${PLAIN}"
                read -n 1 -s -r -p "按任意键继续..."
                command -v nano >/dev/null 2>&1 || sudo apt install -y nano
                sudo nano /etc/hysteria/config.yaml
                press_any_key
                ;;
            3)
                config_file="/etc/hysteria/config.yaml"
                [ ! -f "$config_file" ] && { log_error "未能找到配置文件。"; exit 1; }
                
                sudo systemctl restart hysteria-server.service
                sleep 2
                if ! systemctl is-active --quiet hysteria-server.service; then
                    log_error "未能启动 hysteria 服务，请检查日志。"
                    sudo systemctl status hysteria-server.service --no-pager
                else
                    log_success "hysteria已启动！"
                    port=$(grep "^listen:" "$config_file" | awk -F: '{print $3}' || echo "443")
                    password=$(grep "^  password:" "$config_file" | awk '{print $2}')
                    domain=$(grep "domains:" "$config_file" -A 1 | tail -n 1 | tr -d " -")
                    
                    if [ -z "$domain" ]; then
                        cert_path=$(grep "cert:" "$config_file" | awk '{print $2}' | tr -d '"')
                        domain=$(get_domain_from_cert "$cert_path")
                    fi
                    
                    ip=$(get_public_ip)
                    if [[ "$ip" =~ : ]]; then ip="[$ip]"; fi

                    hysteria2_uri="hysteria2://$password@$ip:$port?sni=$domain&insecure=0#hysteria"
                    echo "hysteria2 链接如下："
                    echo -e "${BLUE}$hysteria2_uri${PLAIN}"
                fi
                press_any_key
                ;;
            4)
                default_redirect_port=443; default_start_port=60000; default_end_port=65535
                config_file="/etc/hysteria/config.yaml"
                redirect_port=$( [ -f "$config_file" ] && grep 'listen:' "$config_file" | awk -F':' '{print $NF}' )
                [[ -z "$redirect_port" || ! "$redirect_port" =~ ^[0-9]+$ ]] && redirect_port="$default_redirect_port"
                
                read -p "请输入起始端口号 (默认 60000): " start_port
                [[ -z "$start_port" ]] && start_port="$default_start_port"
                read -p "请输入结束端口号 (默认 65535): " end_port
                [[ -z "$end_port" ]] && end_port="$default_end_port"
                
                interfaces=($(ip -o link | awk -F': ' '{if ($2 != "lo") print $2}'))
                [[ ${#interfaces[@]} -eq 0 ]] && { log_error "未找到网络接口"; exit 1; }
                selected_interface="${interfaces[0]}"
                
                iptables_command="iptables -t nat -A PREROUTING -i $selected_interface -p udp --dport $start_port:$end_port -j REDIRECT --to-ports $redirect_port"
                if eval "$iptables_command"; then
                    log_success "端口跳跃设置成功!"
                else
                    log_error "iptables命令执行失败。"
                fi
                press_any_key
                ;;
            5)
                if bash <(curl -fsSL https://get.hy2.sh/) --remove && rm -rf /etc/hysteria && \
                   userdel -r hysteria && rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server* && systemctl daemon-reload; then
                    log_success "hysteria2 已卸载。"
                fi
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项" ;;
        esac
    done
}

# =============================================================================
# 8. Sing-box 安装模块
# =============================================================================

install_sing_box() {
    while true; do
        print_header "安装 sing-box"
        echo "1) 安装升级"
        echo "2) 编辑配置"
        echo "3) 重启服务"
        echo "4) 卸载服务"
        echo "========================================="
        read -p "请输入数字 [1-4] 选择 (默认回车退出)：" s_choice
        case "$s_choice" in
            1)
                if bash <(curl -fsSL https://sing-box.app/deb-install.sh) && \
                   sudo curl -L -o /etc/sing-box/config.json "https://raw.githubusercontent.com/sezhai/VPS-Script/refs/heads/main/extras/sing-box/config.json"; then
                    log_success "sing-box 安装升级成功！"
                    echo -e "UUID: ${BLUE}$(sing-box generate uuid)${PLAIN}"
                    keys=$(sing-box generate reality-keypair)
                    export PRIVATE_KEY=$(echo "$keys" | awk '/PrivateKey/ {print $2}')
                    export PUBLIC_KEY=$(echo "$keys" | awk '/PublicKey/  {print $2}')
                    echo -e "PrivateKey: ${BLUE}$PRIVATE_KEY${PLAIN}"
                    echo -e "ShortIds: ${BLUE}$(sing-box generate rand 8 --hex)${PLAIN}"
                else
                    log_error "sing-box 安装升级失败！"
                fi
                press_any_key
                ;;
            2)
                echo -e "${YELLOW}提示：根据提示修改配置文件。${PLAIN}"
                read -n 1 -s -r -p "按任意键继续..."
                command -v nano >/dev/null 2>&1 || sudo apt install -y nano
                sudo nano /etc/sing-box/config.json
                press_any_key
                ;;
            3)
                CONFIG_PATH="/etc/sing-box/config.json"
                sudo systemctl restart sing-box
                sleep 2
                if ! systemctl is-active --quiet sing-box; then
                    log_error "未能启动 sing-box 服务，请检查日志。"
                    systemctl status sing-box --no-pager
                else
                    log_success "sing-box已启动！"
                    
                    ip=$(get_public_ip)
                    if [[ "$ip" =~ : ]]; then ip_for_url="[$ip]"; else ip_for_url="$ip"; fi
                    
                    urlencode() {
                        local s="$1" ch; for ((i=0; i<${#s}; i++)); do ch="${s:i:1}"; case "$ch" in [a-zA-Z0-9.~_-]) printf '%s' "$ch" ;; *) printf '%%%02X' "'$ch" ;; esac; done
                    }
                    
                    if grep -q '"tag":\s*"vmess"' "$CONFIG_PATH"; then
                        vmess_uuid=$(grep -A 20 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"uuid":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
                        vmess_port=$(grep -A 5 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')
                        vmess_path=$(grep -A 30 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"path":\s*"[^"]*"' | cut -d'"' -f4)
                        vmess_host=$(grep -A 30 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"server_name":\s*"[^"]*"' | cut -d'"' -f4)
                        if [[ -n "$vmess_uuid" && -n "$vmess_port" ]]; then
                            vmess_json='{"v":"2","ps":"vmess","add":"'$ip'","port":"'$vmess_port'","id":"'$vmess_uuid'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'$vmess_host'","path":"'$vmess_path'","tls":"tls","sni":"'$vmess_host'","alpn":"http/1.1","fp":"chrome"}'
                            echo "vmess 链接如下："
                            echo -e "${BLUE}vmess://$(echo -n "$vmess_json" | base64 -w0)${PLAIN}"
                        fi
                    fi
                    
                    if grep -q '"tag":\s*"reality"' "$CONFIG_PATH"; then
                        vless_uuid=$(grep -A 20 '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"uuid":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
                        vless_port=$(grep -A 5 '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')
                        vless_sni=$(grep -A 30 '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"server_name":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
                        vless_sid=$(grep -A 30 '"tag":\s*"reality"' "$CONFIG_PATH" | sed -n '/"short_id"/,/]/p' | grep -o '"[a-fA-F0-9]*"' | head -1 | tr -d '"')
                        if [[ -n "$vless_uuid" && -n "$vless_port" ]]; then
                             vless_link="vless://$vless_uuid@$ip_for_url:$vless_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vless_sni&fp=chrome&pbk=$PUBLIC_KEY&sid=$vless_sid&type=tcp&headerType=none#reality"
                             echo "reality 链接如下："
                             echo -e "${BLUE}$vless_link${PLAIN}"
                        fi
                    fi
                    
                    if grep -q '"tag":\s*"hysteria2"' "$CONFIG_PATH"; then
                        h2_pass=$(grep -A 20 '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"password":\s*"[^"]*"' | cut -d'"' -f4)
                        h2_port=$(grep -A 5 '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')
                        cert_path=$(grep -A 30 '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"certificate_path":\s*"[^"]*"' | cut -d'"' -f4)
                        if [[ -n "$h2_pass" && -n "$h2_port" && -f "$cert_path" ]]; then
                            h2_domain=$(get_domain_from_cert "$cert_path")
                            [[ -n "$h2_domain" ]] && echo -e "hysteria2 链接如下：\n${BLUE}hysteria2://$(urlencode "$h2_pass")@$ip_for_url:$h2_port?sni=$h2_domain&insecure=0#hysteria2${PLAIN}"
                        fi
                    fi
                fi
                press_any_key
                ;;
            4)
                if systemctl disable --now sing-box && rm -f /usr/local/bin/sing-box /etc/systemd/system/sing-box.service && rm -rf /var/lib/sing-box /etc/sing-box; then
                    log_success "sing-box 已卸载。"
                fi
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项" ;;
        esac
    done
}

# =============================================================================
# 9. 1Panel 安装模块
# =============================================================================

install_1panel() {
    while true; do
        print_header "安装 1Panel"
        echo "1) 安装面板"
        echo "2) 查看信息"
        echo "3) 安装防火墙 (ufw)"
        echo "4) 卸载防火墙"
        echo "5) 卸载面板"
        echo "========================================="
        read -p "请输入数字 [1-5] 选择 (默认回车退出)：" p_choice
        case "$p_choice" in
            1)
                curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && sudo bash quick_start.sh
                check_status "1Panel 安装"
                press_any_key
                ;;
            2)
                1pctl user-info
                press_any_key
                ;;
            3)
                sudo apt install ufw
                check_status "ufw 安装"
                press_any_key
                ;;
            4)
                sudo apt remove -y ufw && sudo apt purge -y ufw && sudo apt autoremove -y
                check_status "ufw 卸载"
                press_any_key
                ;;
            5)
                if sudo systemctl stop 1panel && sudo 1pctl uninstall && sudo rm -rf /var/lib/1panel /etc/1panel /usr/local/bin/1pctl && \
                   sudo journalctl --vacuum-time=3d && \
                   sudo systemctl stop docker && sudo apt-get purge -y docker-ce docker-ce-cli containerd.io && \
                   sudo find / \( -name "1panel*" -or -name "docker*" -or -name "containerd*" -or -name "compose*" \) -exec rm -rf {} + && \
                   sudo groupdel docker; then
                   log_success "1Panel 卸载完成。"
                fi
                press_any_key
                ;;
            "") return ;;
            *) log_error "无效选项" ;;
        esac
    done
}

# =============================================================================
# 主菜单
# =============================================================================

display_main_menu() {
    clear
    echo "========================================="
    echo -e "               ${CYAN}VPS管理脚本${PLAIN}"
    echo "========================================="
    echo "1) 系统信息"
    echo "2) 系统优化"
    echo "3) 常用工具"
    echo "4) 常用软件包"
    echo "5) 申请证书"
    echo "6) 安装Xray"
    echo "7) 安装hysteria2"
    echo "8) 安装sing-box"
    echo "9) 安装1Panel"
    echo "========================================="
}

while true; do
    display_main_menu
    read -p "请输入数字 [1-9] 选择(默认回车退出)：" choice
    if [[ -z "$choice" ]]; then
        log_success "退出脚本，感谢使用！"
        exit 0
    fi
    case "$choice" in
        1) view_vps_info ;;
        2) display_system_optimization_menu ;;
        3) common_tools ;;
        4) install_package ;;
        5) apply_certificate ;;
        6) install_xray ;;
        7) install_hysteria2 ;;
        8) install_sing_box ;;
        9) install_1panel ;;
        *) log_error "无效选项，请输入数字 1-9 或直接回车退出！" ;;
    esac
done
