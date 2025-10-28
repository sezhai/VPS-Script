#!/usr/bin/env bash
# VPS 管理脚本（Debian/Ubuntu 优化版）

set -Eeuo pipefail
shopt -s extglob

# ----------------------------[ 全局/工具函数 ]----------------------------
export LC_ALL=C
if [[ ${TERM-} != "dumb" ]]; then
  RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; CYAN='\e[36m'; BOLD='\e[1m'; RESET='\e[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; RESET=''
fi

cecho() { # cecho COLOR "msg"
  local color="$1"; shift || true
  echo -e "${color}$*${RESET}"
}

pause() {
  read -n 1 -s -r -p "按任意键返回..."
  echo
}

# root / sudo 统一
if (( EUID == 0 )); then SUDO=""; else SUDO="sudo"; fi

# 仅执行一次 apt update
APT_UPDATED=0
apt_update_once() {
  if (( APT_UPDATED == 0 )); then
    $SUDO apt-get update -y -qq
    APT_UPDATED=1
  fi
}

# 确保安装包（支持一次装多个）
ensure_pkg() {
  local need=()
  for p in "$@"; do
    dpkg -s "$p" &>/dev/null || need+=("$p")
  done
  if ((${#need[@]})); then
    apt_update_once
    $SUDO apt-get install -y -qq "${need[@]}"
  fi
}

# 统一下载：curl→wget→自动装curl
fetch() {
  local url="$1"; local out="${2-}"
  local curl_opts=( -fsSL --connect-timeout 10 --retry 3 )
  local wget_opts=( -q --tries=3 --timeout=15 )
  if command -v curl >/dev/null 2>&1; then
    if [[ -n "$out" ]]; then curl "${curl_opts[@]}" "$url" -o "$out"; else curl "${curl_opts[@]}" "$url"; fi
  elif command -v wget >/dev/null 2>&1; then
    if [[ -n "$out" ]]; then wget "${wget_opts[@]}" -O "$out" "$url"; else wget -q -O - "$url"; fi
  else
    cecho "$YELLOW" "未检测到 curl/wget，尝试安装 curl ..."
    ensure_pkg curl
    if [[ -n "$out" ]]; then curl "${curl_opts[@]}" "$url" -o "$out"; else curl "${curl_opts[@]}" "$url"; fi
  fi
}

# 默认路由网卡
default_iface() {
  ip route get 1.1.1.1 2>/dev/null | awk '/dev/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

# 读取 /etc/os-release
os_pretty() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "${PRETTY_NAME:-Linux}"
  else
    lsb_release -ds 2>/dev/null || uname -sr
  fi
}

# ----------------------------[ 主菜单 ]----------------------------
display_main_menu() {
  clear
  echo "========================================="
  echo -e "               ${BOLD}${CYAN}VPS管理脚本${RESET}"
  echo "========================================="
  echo "1) 系统信息"
  echo "2) 系统优化"
  echo "3) 常用工具"
  echo "4) 常用软件包"
  echo "5) 申请证书"
  echo "6) 安装Xray"
  echo "7) 安装Hysteria2"
  echo "8) 安装sing-box"
  echo "9) 安装1Panel"
  echo "========================================="
}

# ----------------------------[ 系统信息 ]----------------------------
view_vps_info() {
  cecho "$BLUE" "主机名: ${GREEN}$(hostname)${RESET}"
  cecho "$BLUE" "系统版本: ${GREEN}$(os_pretty)${RESET}"
  cecho "$BLUE" "Linux版本: ${GREEN}$(uname -r)${RESET}"
  echo "-------------"
  cecho "$BLUE" "CPU架构: ${GREEN}$(uname -m)${RESET}"
  cecho "$BLUE" "CPU型号: ${GREEN}$(lscpu | awk -F: '/Model name/{gsub(/^[ \t]+/,"",$2);print $2; exit}')${RESET}"
  cecho "$BLUE" "CPU核心数: ${GREEN}$(nproc)${RESET}"
  cecho "$BLUE" "CPU频率: ${GREEN}$(lscpu | awk -F: '/CPU MHz/{gsub(/^[ \t]+/,"",$2);print $2; exit}') MHz${RESET}"
  echo "-------------"
  cecho "$BLUE" "CPU占用: ${GREEN}$(LANG=C top -bn1 | awk -F'[ ,]+' '/Cpu\\(s\\)/{printf "%.1f", $2+$4}')%${RESET}"
  cecho "$BLUE" "系统负载: ${GREEN}$(awk '{print $1, $2, $3}' /proc/loadavg)${RESET}"
  local mem_info swap_info
  mem_info=$(free -m | awk '/Mem:/{printf "%.2f/%.2f MB (%.2f%%)", $3, $2, ($2>0)?($3*100/$2):0}')
  swap_info=$(free -m | awk '/Swap:/{printf "%dMB/%dMB (%.0f%%)", $3, $2, ($2>0)?($3*100/$2):0}')
  cecho "$BLUE" "物理内存: ${GREEN}${mem_info}${RESET}"
  cecho "$BLUE" "虚拟内存: ${GREEN}${swap_info}${RESET}"
  cecho "$BLUE" "硬盘占用: ${GREEN}$(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')${RESET}"
  echo "-------------"
  local IFACE RX_BYTES TX_BYTES
  IFACE="$(default_iface || true)"
  [[ -z "$IFACE" ]] && IFACE="$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')"
  if [[ -n "$IFACE" && -r /sys/class/net/$IFACE/statistics/rx_bytes ]]; then
    RX_BYTES=$(<"/sys/class/net/$IFACE/statistics/rx_bytes")
    TX_BYTES=$(<"/sys/class/net/$IFACE/statistics/tx_bytes")
    printf "\e[1;34m网络接口:\e[0m \e[32m%s\e[0m\n" "$IFACE"
    printf "\e[1;34m总接收:\e[0m \e[32m%.2f MB\e[0m\n" "$(awk "BEGIN{print $RX_BYTES/1024/1024}")"
    printf "\e[1;34m总发送:\e[0m \e[32m%.2f MB\e[0m\n" "$(awk "BEGIN{print $TX_BYTES/1024/1024}")"
  else
    cecho "$RED" "未检测到有效的网络接口！"
  fi
  echo "-------------"
  if [[ -f /proc/sys/net/ipv4/tcp_congestion_control ]]; then
    cecho "$BLUE" "网络算法: ${GREEN}$(sysctl -n net.ipv4.tcp_congestion_control)${RESET}"
  else
    cecho "$BLUE" "网络算法: ${RED}IPv4 未启用或不支持。${RESET}"
  fi
  echo "-------------"
  # 一次性获取 ipinfo JSON
  local ipjson org city country
  ipjson="$(fetch "https://ipinfo.io/json" || true)"
  org="$(sed -n 's/.*"org":[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$ipjson")"
  city="$(sed -n 's/.*"city":[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$ipjson")"
  country="$(sed -n 's/.*"country":[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$ipjson")"
  cecho "$BLUE" "运营商: ${GREEN}${org:-N/A}${RESET}"
  cecho "$BLUE" "IPv4地址: ${GREEN}$(fetch "https://ipv4.icanhazip.com" | tr -d '\n' || echo N/A)${RESET}"
  cecho "$BLUE" "IPv6地址: ${GREEN}$(ip -6 addr show scope global | awk '/inet6/&&!/temporary|tentative/{print $2}' | cut -d/ -f1 | head -n1 || echo "未检测到IPv6地址")${RESET}"
  cecho "$BLUE" "DNS地址: ${GREEN}$(awk '/^nameserver/{print $2}' /etc/resolv.conf | xargs | sed 's/ /, /g')${RESET}"
  cecho "$BLUE" "地理位置: ${GREEN}${city:-N/A}, ${country:-N/A}${RESET}"
  cecho "$BLUE" "系统时间: ${GREEN}$(timedatectl 2>/dev/null | awk -F': ' '/Local time/{print $2}')${RESET}"
  echo "-------------"
  cecho "$BLUE" "运行时长: ${GREEN}$(uptime -p | sed 's/^up //')${RESET}"
  echo "-------------"
  pause
}

# ----------------------------[ 系统优化菜单 ]----------------------------
display_system_optimization_menu() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${GREEN}系统优化${RESET}       "
    echo "========================================="
    echo "1) 校准时间"
    echo "2) 更新系统"
    echo "3) 清理系统"
    echo "4) 开启BBR"
    echo "5) ROOT登录"
    echo "6) 系统初始化"
    echo "========================================="
    read -r -p "请输入数字 [1-6] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1) calibrate_time ;;
      2) update_system ;;
      3) clean_system ;;
      4) enable_bbr ;;
      5) root_login ;;
      6) user_sysinit ;;
      "") return ;;
      *) cecho "$RED" "无效选项，请重新输入。" ;;
    esac
  done
}

# ----------------------------[ 时间校准 ]----------------------------
calibrate_time() {
  echo -e "\n[校准时间]"
  $SUDO timedatectl set-timezone Asia/Shanghai
  $SUDO timedatectl set-ntp true
  cecho "$GREEN" "时间校准完成，当前时区为 Asia/Shanghai。"
  pause
}

# ----------------------------[ 系统更新 ]----------------------------
update_system() {
  echo -e "\n[更新系统]"
  # 修正原脚本逻辑：任一步失败都算失败（用 ||）
  if ! $SUDO apt-get update -y || ! $SUDO apt-get full-upgrade -y; then
    cecho "$RED" "系统更新失败！请检查网络连接或源列表。"
  else
    $SUDO apt-get autoremove -y && $SUDO apt-get autoclean -y
    cecho "$GREEN" "系统更新完成！"
  fi
  pause
}

# ----------------------------[ 系统清理 ]----------------------------
clean_system() {
  echo -e "\n[清理系统]"
  $SUDO apt-get autoremove --purge -y
  $SUDO apt-get clean -y && $SUDO apt-get autoclean -y
  $SUDO journalctl --rotate || true
  $SUDO journalctl --vacuum-time=10m || true
  $SUDO journalctl --vacuum-size=50M || true
  cecho "$GREEN" "系统清理完成！"
  pause
}

# ----------------------------[ 开启BBR ]----------------------------
enable_bbr() {
  echo -e "\n[开启BBR]"
  # 是否已开启
  if sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -q '^bbr$'; then
    cecho "$GREEN" "BBR已开启！"
    pause; return
  fi
  # 是否支持
  if ! sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
    cecho "$RED" "内核不支持 BBR（net.ipv4.tcp_available_congestion_control 无 bbr）。"
    pause; return
  fi
  # 写入到 sysctl.d，避免反复追加 sysctl.conf
  echo "net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr" | $SUDO tee /etc/sysctl.d/99-bbr.conf >/dev/null
  if $SUDO sysctl --system >/dev/null 2>&1; then
    cecho "$GREEN" "BBR已开启！"
  else
    cecho "$RED" "BBR 开启失败！"
  fi
  pause
}

# ----------------------------[ ROOT登录 ]----------------------------
root_login() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${BLUE}ROOT登录${RESET}   "
    echo "========================================="
    echo "1) 设置密码"
    echo "2) 修改配置"
    echo "3) 重启服务"
    echo "========================================="
    read -r -p "请输入数字 [1-3] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1)
        $SUDO passwd root
        pause
        ;;
      2)
        $SUDO sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
        $SUDO sed -i 's/^\s*#\?\s*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
        cecho "$GREEN" "配置修改成功！"
        pause
        ;;
      3)
        if $SUDO systemctl restart sshd.service; then
          cecho "$GREEN" "ROOT登录已开启！"
        else
          cecho "$RED" "ROOT登录开启失败！"
        fi
        pause
        ;;
      "") return ;;
      *) cecho "$RED" "无效选项，请重新输入。" ;;
    esac
  done
}

# ----------------------------[ 系统初始化（危险操作） ]----------------------------
user_sysinit() {
  set -e
  read -r -p "$(echo -e '\033[0;31m输入y继续（默认回车退出）:\033[0m ') " confirm
  [[ "${confirm:-}" != "y" ]] && return 0

  echo "开始系统清理..."
  cecho "$BLUE" "[INFO] 清理后装应用文件..."
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
      $SUDO rm -rf -- "$path" 2>/dev/null && cecho "$BLUE" "[INFO] 删除: $path"
    fi
  done

  cecho "$BLUE" "[INFO] 清理后装systemd服务..."
  local CLEANUP_SERVICES=(
    "xray" "v2ray" "sing-box" "hysteria" "hysteria2" "hy2"
    "clash" "trojan" "caddy" "frps" "frpc" "1panel"
    "nezha-agent" "nezha-dashboard" "aria2" "filebrowser"
    "portainer" "docker" "containerd"
  )
  for service in "${CLEANUP_SERVICES[@]}"; do
    $SUDO systemctl stop "$service" 2>/dev/null || true
    $SUDO systemctl disable "$service" 2>/dev/null || true
    $SUDO rm -f "/etc/systemd/system/${service}.service" "/etc/systemd/system/${service}d.service" \
               "/etc/systemd/system/${service}-agent.service" "/etc/systemd/system/${service}-dashboard.service"
  done
  $SUDO systemctl daemon-reload 2>/dev/null || true

  cecho "$BLUE" "[INFO] 终止后装应用进程..."
  local KILL_PATTERNS=( "xray" "v2ray" "sing-box" "hysteria" "clash" "trojan" "caddy" "frps" "frpc" "1panel" "nezha" "aria2" "filebrowser" "portainer" "docker" "containerd" )
  for pattern in "${KILL_PATTERNS[@]}"; do
    $SUDO pkill -f "$pattern" 2>/dev/null || true
  done

  cecho "$BLUE" "[INFO] 删除后装APT包..."
  local REMOVE_PKGS=( "docker.io" "docker-ce" "docker-compose" "containerd.io" "docker-compose-plugin" )
  for pkg in "${REMOVE_PKGS[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
      cecho "$BLUE" "[INFO] 删除APT包: $pkg"
      $SUDO apt-get remove --purge -y "$pkg" -qq 2>/dev/null || true
    fi
  done

  cecho "$BLUE" "[INFO] 清理用户目录..."
  for home in /home/*/; do
    [[ -d "$home" ]] || continue
    $SUDO rm -rf -- "${home}.config/1panel" "${home}.config/clash" "${home}.config/v2ray" \
                     "${home}.xray" "${home}.v2ray" 2>/dev/null || true
  done

  cecho "$BLUE" "[INFO] 清理缓存..."
  $SUDO rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
  $SUDO apt-get autoclean -qq || true
  $SUDO apt-get clean -qq || true

  cecho "$BLUE" "[INFO] 验证系统完整性..."
  $SUDO dpkg --configure -a --force-confold 2>/dev/null || true
  $SUDO apt-get update -qq 2>/dev/null || {
    cecho "$BLUE" "[INFO] 尝试修复APT..."
    $SUDO apt-get -f install -y -qq 2>/dev/null || true
    $SUDO apt-get update -qq 2>/dev/null || true
  }

  for service in systemd-resolved systemd-networkd networking; do
    if $SUDO systemctl is-enabled "$service" >/dev/null 2>&1; then
      $SUDO systemctl restart "$service" 2>/dev/null || true
    fi
  done

  cecho "$GREEN" "系统初始化完成！"
  read -r -p "$(echo -e '\033[0;31m输入y重启系统（默认回车退出）:\033[0m ') " reboot_choice
  [[ "${reboot_choice:-}" == "y" ]] && $SUDO reboot
  pause
}

# ----------------------------[ 常用工具 ]----------------------------
common_tools() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${GREEN}常用工具${RESET} "
    echo "========================================="
    echo "1) 查找文件"
    echo "2) 赋予权限"
    echo "3) 删除文件"
    echo "4) 查看进程"
    echo "5) 关闭进程"
    echo "6) 查看端口"
    echo "7) 开放端口"
    echo "8) 网络测速"
    echo "========================================="
    read -r -p "请输入数字 [1-8] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1)
        read -r -p "请输入要查找的文件名: " filename
        if [[ -z "${filename:-}" ]]; then
          cecho "$RED" "文件名不能为空。"
        else
          find / -type f -name "*$filename*" 2>/dev/null || cecho "$RED" "未找到匹配的文件。"
        fi
        pause
        ;;
      2)
        read -r -p "请输入文件路径: " file_path
        if [[ ! -e "$file_path" ]]; then
          cecho "$RED" "错误: 文件或目录 '$file_path' 不存在。"
        else
          if $SUDO chmod 755 -- "$file_path"; then
            cecho "$GREEN" "'$file_path' 权限已设置为 755！"
          else
            cecho "$RED" "错误: 设置 '$file_path' 权限为 755 失败。"
          fi
        fi
        pause
        ;;
      3)
        while true; do
          read -r -p "请输入要删除的文件或目录名（默认回车退出）: " filename
          [[ -z "${filename:-}" ]] && break
          mapfile -t files < <(find / \( -type f -o -type d \) -iname "*$filename*" 2>/dev/null)
          if ((${#files[@]}==0)); then
            cecho "$RED" "未找到匹配的文件或目录。"; continue
          fi
          echo "找到以下文件或目录:"
          for i in "${!files[@]}"; do
            echo "$((i+1)). ${files[$i]}"
          done
          read -r -p "请输入要删除的编号（可多选，空格分隔，回车取消）: " choices
          [[ -z "${choices:-}" ]] && echo "取消删除操作。" && continue
          read -r -a choice_array <<< "$choices"
          for choice in "${choice_array[@]}"; do
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#files[@]} )); then
              file="${files[$((choice-1))]}"
              read -r -p "确定要删除 $file 吗？ (y/n): " confirm
              if [[ "$confirm" == "y" ]]; then
                if [[ -d "$file" ]]; then $SUDO rm -rf -- "$file"; cecho "$GREEN" "目录已删除: $file"
                else $SUDO rm -f -- "$file"; cecho "$GREEN" "文件已删除: $file"; fi
              else
                echo "取消删除 $file。"
              fi
            else
              cecho "$RED" "无效的选择: $choice"
            fi
          done
        done
        pause
        ;;
      4)
        ps aux
        pause
        ;;
      5)
        while true; do
          read -r -p "请输入要关闭的进程 PID: " pid
          if [[ "$pid" =~ ^[0-9]+$ ]]; then
            if $SUDO kill "$pid" 2>/dev/null; then
              cecho "$GREEN" "进程 $pid 已成功关闭！"
            else
              cecho "$RED" "进程 $pid 无法正常关闭 (SIGTERM)。"
              read -r -p "是否需要强制关闭 (SIGKILL)？ (y/n): " choice
              if [[ "$choice" == "y" ]]; then
                if $SUDO kill -9 "$pid" 2>/dev/null; then cecho "$GREEN" "进程 $pid 已被强制关闭！"
                else cecho "$RED" "进程 $pid 强制关闭失败。"; fi
              else
                echo "取消强制关闭。"
              fi
            fi
            break
          else
            cecho "$RED" "无效的 PID，请输入一个整数。"
          fi
        done
        pause
        ;;
      6)
        if command -v ss >/dev/null 2>&1; then
          echo -e "端口     类型    程序名               PID"
          ss -tulnpH | awk '{
            split($5, a, ":"); split($7,b,",");
            gsub(/[()]/,"",b[1]); gsub(/pid=/,"",b[2]); gsub(/users:/,"",b[1]); gsub(/"/,"",b[1]);
            port=a[length(a)];
            if(port!="" && port!="*"){ printf "%-8s %-7s %-20s %-6s\n", port, $1, b[1], b[2]; }
          }'
        else
          ensure_pkg net-tools
          echo -e "端口     类型    程序名               PID"
          netstat -tulnp 2>/dev/null | awk 'NR>2{
            split($4,a,":"); split($7,b,"/");
            gsub(/[()]/,"",b[1]); gsub(/pid=/,"",b[2]); gsub(/users:/,"",b[1]); gsub(/"/,"",b[1]);
            if(a[2]!="" && a[2]!="*"){ printf "%-8s %-7s %-20s %-6s\n", a[2], $1, b[1], b[2];}
          }'
        fi
        pause
        ;;
      7)
        local protocol port
        while true; do
          echo "请选择协议: 1) TCP  2) UDP"
          read -r -p "请输入1或2: " p
          case "${p:-}" in
            1) protocol="tcp"; break ;;
            2) protocol="udp"; break ;;
            *) cecho "$RED" "无效的选择，请输入1或2。";;
          esac
        done
        while true; do
          read -r -p "请输入端口号: " port
          if [[ "$port" =~ ^[0-9]+$ ]] && (( port>=1 && port<=65535 )); then break
          else cecho "$RED" "无效的端口号，请输入1到65535之间的数字。"; fi
        done
        if $SUDO iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT; then
          cecho "$GREEN" "端口 $port 已开放（$protocol）!"
        else
          cecho "$RED" "执行命令失败。"
        fi
        pause
        ;;
      8)
        if ! command -v speedtest-cli >/dev/null 2>&1; then
          cecho "$YELLOW" "未检测到 speedtest-cli，正在安装..."
          ensure_pkg speedtest-cli
        else
          echo "已安装 speedtest-cli，直接测速..."
        fi
        echo "开始测速..."
        speedtest-cli || cecho "$RED" "测速失败。"
        pause
        ;;
      "")
        return
        ;;
      *)
        cecho "$RED" "无效选项，请重新输入。"
        ;;
    esac
  done
}

# ----------------------------[ 常用软件包 ]----------------------------
install_package() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${GREEN}常用软件包${RESET}   "
    echo "========================================="
    echo "1) apt"
    echo "2) sudo"
    echo "3) wget"
    echo "4) nano"
    echo "5) vim"
    echo "6) zip"
    echo "7) git"
    echo "8) htop"
    echo "9) docker"
    echo "========================================="
    read -r -p "请输入数字 [1-9] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1)
        if $SUDO apt-get update -y; then cecho "$GREEN" "apt 更新完成！"
        else cecho "$RED" "apt 更新失败！请检查网络连接或源列表。"; fi
        pause
        ;;
      2)
        echo "1) 安装  2) 卸载"
        read -r -p "请选择操作 (默认回车退出)：" act
        case "${act:-}" in
          1) apt_update_once; $SUDO apt-get install -y sudo && cecho "$GREEN" "sudo 安装完成！" || cecho "$RED" "sudo 安装失败！" ;;
          2) apt_update_once; $SUDO apt-get remove -y sudo && cecho "$GREEN" "sudo 卸载完成！" || cecho "$RED" "sudo 卸载失败！" ;;
          "") ;;
          *) cecho "$RED" "无效选项。" ;;
        esac
        pause
        ;;
      3)
        echo "1) 安装  2) 卸载"
        read -r -p "请选择操作 (默认回车退出)：" act
        case "${act:-}" in
          1) ensure_pkg wget; cecho "$GREEN" "wget 安装完成！" ;;
          2) $SUDO apt-get remove -y wget && cecho "$GREEN" "wget 卸载完成！" || cecho "$RED" "wget 卸载失败！" ;;
          "") ;;
          *) cecho "$RED" "无效选项。" ;;
        esac
        pause
        ;;
      4)
        echo "1) 安装  2) 卸载"
        read -r -p "请选择操作 (默认回车退出)：" act
        case "${act:-}" in
          1) ensure_pkg nano; cecho "$GREEN" "nano 安装完成！" ;;
          2) $SUDO apt-get remove -y nano && cecho "$GREEN" "nano 卸载完成！" || cecho "$RED" "nano 卸载失败！" ;;
          "") ;;
          *) cecho "$RED" "无效选项。" ;;
        esac
        pause
        ;;
      5)
        echo "1) 安装  2) 卸载"
        read -r -p "请选择操作 (默认回车退出)：" act
        case "${act:-}" in
          1) ensure_pkg vim; cecho "$GREEN" "vim 安装完成！" ;;
          2) $SUDO apt-get remove -y vim && cecho "$GREEN" "vim 卸载完成！" || cecho "$RED" "vim 卸载失败！" ;;
          "") ;;
          *) cecho "$RED" "无效选项。" ;;
        esac
        pause
        ;;
      6)
        echo "1) 安装  2) 卸载"
        read -r -p "请选择操作 (默认回车退出)：" act
        case "${act:-}" in
          1) ensure_pkg zip; cecho "$GREEN" "zip 安装完成！" ;;
          2) $SUDO apt-get remove -y zip && cecho "$GREEN" "zip 卸载完成！" || cecho "$RED" "zip 卸载失败！" ;;
          "") ;;
          *) cecho "$RED" "无效选项。" ;;
        esac
        pause
        ;;
      7)
        echo "1) 安装  2) 卸载"
        read -r -p "请选择操作 (默认回车退出)：" act
        case "${act:-}" in
          1) ensure_pkg git; cecho "$GREEN" "git 安装完成！" ;;
          2) $SUDO apt-get remove -y git && cecho "$GREEN" "git 卸载完成！" || cecho "$RED" "git 卸载失败！" ;;
          "") ;;
          *) cecho "$RED" "无效选项。" ;;
        esac
        pause
        ;;
      8)
        echo "1) 安装  2) 卸载"
        read -r -p "请选择操作 (默认回车退出)：" act
        case "${act:-}" in
          1) ensure_pkg htop; cecho "$GREEN" "htop 安装完成！" ;;
          2) $SUDO apt-get remove -y htop && cecho "$GREEN" "htop 卸载完成！" || cecho "$RED" "htop 卸载失败！" ;;
          "") ;;
          *) cecho "$RED" "无效选项。" ;;
        esac
        pause
        ;;
      9)
        echo "1) 安装  2) 卸载"
        read -r -p "请选择操作 (默认回车退出)：" act
        case "${act:-}" in
          1)
            if fetch "https://get.docker.com/" | $SUDO sh; then cecho "$GREEN" "docker 安装完成！"
            else cecho "$RED" "docker 安装失败！"; fi
            ;;
          2)
            if $SUDO apt-get remove -y docker && $SUDO apt-get autoremove -y; then cecho "$GREEN" "docker 卸载完成！"
            else cecho "$RED" "docker 卸载失败！"; fi
            ;;
          "") ;;
          *) cecho "$RED" "无效选项。" ;;
        esac
        pause
        ;;
      "")
        return
        ;;
      *)
        cecho "$RED" "无效选项，请重新输入。"
        ;;
    esac
  done
}

# ----------------------------[ 申请证书（acme.sh） ]----------------------------
apply_certificate() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${GREEN}申请证书${RESET}     "
    echo "========================================="
    echo "1) 安装脚本"
    echo "2) 申请证书"
    echo "3) 更换服务器"
    echo "4) 安装证书"
    echo "5) 卸载脚本"
    echo "========================================="
    read -r -p "请输入数字 [1-5] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1)
        read -r -p "请输入邮箱地址: " email
        apt_update_once
        ensure_pkg cron socat
        if fetch "https://get.acme.sh" | sh -s email="$email"; then
          cecho "$GREEN" "acme.sh 安装完成！"
        else
          cecho "$RED" "acme.sh 安装失败！"
        fi
        pause
        ;;
      2)
        read -r -p "请输入域名: " domain
        if ~/.acme.sh/acme.sh --issue --standalone -d "$domain"; then
          cecho "$GREEN" "证书申请成功！"
        else
          cecho "$RED" "证书申请失败，请检查域名与解析。"
        fi
        pause
        ;;
      3)
        if ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt; then
          cecho "$GREEN" "已切换至 Let's Encrypt 服务！"
        else
          cecho "$RED" "切换失败，请检查 acme.sh 安装与网络。"
        fi
        pause
        ;;
      4)
        read -r -p "请输入域名: " domain
        read -r -p "请输入证书安装路径（默认: /path/to）: " install_path
        install_path=${install_path:-/path/to}
        if mkdir -p "$install_path" && \
           ~/.acme.sh/acme.sh --installcert -d "$domain" \
             --key-file "$install_path/key.key" \
             --fullchain-file "$install_path/certificate.crt" && \
           $SUDO chmod 644 "$install_path/certificate.crt" "$install_path/key.key"; then
          cecho "$GREEN" "证书安装完成！路径: $install_path"
        else
          cecho "$RED" "证书安装失败，请检查输入。"
        fi
        pause
        ;;
      5)
        if ~/.acme.sh/acme.sh --uninstall; then
          cecho "$GREEN" "acme.sh 已卸载。"
        else
          cecho "$RED" "acme.sh 卸载失败！"
        fi
        pause
        ;;
      "")
        return
        ;;
      *)
        cecho "$RED" "无效选项，请重新输入。"
        ;;
    esac
  done
}

# ----------------------------[ Xray 安装 ]----------------------------
install_xray() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${GREEN}安装Xray${RESET}       "
    echo "========================================="
    echo "1) VMESS-WS-TLS"
    echo "2) VLESS-TCP-REALITY"
    echo "3) 卸载服务"
    echo "========================================="
    read -r -p "请输入数字 [1-3] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1) install_xray_tls ;;
      2) install_xray_reality ;;
      3)
        if fetch "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" | bash -s @ remove --purge; then
          cecho "$GREEN" "Xray已卸载。"
        else
          cecho "$RED" "Xray卸载失败！"
        fi
        pause
        ;;
      "") return ;;
      *) cecho "$RED" "无效选项，请重新输入。" ;;
    esac
  done
}

# VMESS-WS-TLS
install_xray_tls() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${BLUE}VMESS-WS-TLS${RESET}   "
    echo "========================================="
    echo "1) 安装升级"
    echo "2) 编辑配置"
    echo "3) 重启服务"
    echo "========================================="
    read -r -p "请输入数字 [1-3] 选择功能 (默认回车退出)：" sub
    case "${sub:-}" in
      1)
        if fetch "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" | bash -s @ install && \
           fetch "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VMess-Websocket-TLS/config_server.jsonc" "/usr/local/etc/xray/config.json"
        then
          cecho "$GREEN" "Xray 安装升级完成！"
          echo "以下是 UUID："
          cecho "$BLUE" "$(xray uuid)"
        else
          cecho "$RED" "Xray 安装升级失败！"
        fi
        pause
        ;;
      2)
        cecho "$YELLOW" "提示：将 UUID 填入配置文件中。若使用了上述“安装证书”，证书路径一般无需修改。"
        pause
        ensure_pkg nano
        $SUDO nano /usr/local/etc/xray/config.json
        pause
        ;;
      3)
        local CONFIG_PATH="/usr/local/etc/xray/config.json"
        extract_field() { # key regex
          local key="$1" re="$2"
          grep -aPo "\"$key\":\s*$re" "$CONFIG_PATH" | head -n1 | sed -E "s/\"$key\":\s*//;s/^\"//;s/\"$//"
        }
        extract_list_field() { # list_parent list_field
          local lp="$1" lf="$2"
          grep -aPoz "\"$lp\":\s*\[\s*\{[^}]*\}\s*\]" "$CONFIG_PATH" \
            | grep -aPo "\"$lf\":\s*\"[^\"]*\"" | head -n1 | sed -E "s/\"$lf\":\s*\"([^\"]*)\"/\1/"
        }
        get_domain_from_cert() {
          local cert_file="$1"
          openssl x509 -in "$cert_file" -text -noout 2>/dev/null | grep -aPo "DNS:[^,]*" | sed 's/DNS://' | head -n1 \
            || openssl x509 -in "$cert_file" -text -noout 2>/dev/null | grep -aPo "CN=[^ ]*" | sed 's/CN=//'
        }
        get_public_ip() {
          fetch "https://api.ipify.org" || fetch "https://api64.ipify.org" || echo "127.0.0.1"
        }
        $SUDO systemctl restart xray || true
        sleep 2
        if ! systemctl is-active --quiet xray; then
          cecho "$RED" "未能启动 xray 服务，请检查日志。"
          systemctl status xray --no-pager
        else
          cecho "$GREEN" "xray 已启动！"
          local UUID PORT WS_PATH TLS CERT_PATH DOMAIN ADDRESS
          UUID="$(extract_list_field "clients" "id")"
          PORT="$(extract_field "port" "\d+")"
          WS_PATH="$(extract_field "path" "\"[^\"]*\"")"
          TLS="$(extract_field "security" "\"[^\"]*\"")"
          CERT_PATH="$(extract_list_field "certificates" "certificateFile")"
          if [[ -z "${CERT_PATH:-}" ]]; then cecho "$RED" "未能找到证书路径。"; pause; return; fi
          DOMAIN="$(get_domain_from_cert "$CERT_PATH")"
          ADDRESS="$(get_public_ip)"
          WS_PATH="${WS_PATH:-/}"; TLS="${TLS:-tls}"; PORT="${PORT:-443}"
          local vmess_uri="vmess://${UUID}@${ADDRESS}:${PORT}?encryption=none&security=${TLS}&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=${WS_PATH}#Xray"
          echo "vmess 链接如下："
          cecho "$BLUE" "$vmess_uri"
        fi
        pause
        ;;
      "")
        return
        ;;
      *)
        cecho "$RED" "无效选项，请重新输入。"
        ;;
    esac
  done
}

# VLESS-TCP-REALITY
install_xray_reality() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${BLUE}VLESS-TCP-REALITY${RESET}   "
    echo "========================================="
    echo "1) 安装升级"
    echo "2) 编辑配置"
    echo "3) 重启服务"
    echo "========================================="
    read -r -p "请输入数字 [1-3] 选择(默认回车退出)：" sub
    case "${sub:-}" in
      1)
        if fetch "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" | bash -s @ install && \
           fetch "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-TCP-REALITY%20(without%20being%20stolen)/config_server.jsonc" "/usr/local/etc/xray/config.json"
        then
          cecho "$GREEN" "Xray 安装升级完成！"
          echo "以下是 UUID："; cecho "$BLUE" "$(xray uuid)"
          echo "以下是私钥："
          local keys PRIVATE_KEY PUBLIC_KEY
          keys="$(xray x25519)"
          PRIVATE_KEY="$(awk 'NR==1{print $3}' <<<"$keys" | sed 's/^-//')"
          PUBLIC_KEY="$(awk 'NR==2{print $3}' <<<"$keys" | sed 's/^-//')"
          export PRIVATE_KEY PUBLIC_KEY
          cecho "$BLUE" "$PRIVATE_KEY"
          echo "以下是 ShortIds："; cecho "$BLUE" "$(openssl rand -hex 8)"
        else
          cecho "$RED" "Xray 安装升级失败！"
        fi
        pause
        ;;
      2)
        cecho "$YELLOW" "提示：将 UUID、目标网站及私钥填入配置文件中，ShortIds 非必须。"
        pause
        ensure_pkg nano
        $SUDO nano /usr/local/etc/xray/config.json
        pause
        ;;
      3)
        local CONFIG_PATH="/usr/local/etc/xray/config.json"
        remove_spaces_and_quotes() { echo "$1" | sed 's/[[:space:]]*$//;s/^ *//;s/^"//;s/"$//'; }
        extract_field() { local k="$1" re="$2"; grep -aPo "\"$k\":\s*$re" "$CONFIG_PATH" | head -n1 | sed -E "s/\"$k\":\s*//;s/^\"//;s/\"$//"; }
        extract_server_name() { grep -A 5 '"serverNames"' "$CONFIG_PATH" | grep -o '"[^"]*"' | sed -n '2p' | tr -d '"' ; }
        extract_list_field() {
          local list_field="$2"
          if [[ "$list_field" == "shortIds" || "$list_field" == "serverNames" ]]; then
            local result
            result=$(grep -aA 2 "\"$list_field\": \[" "$CONFIG_PATH" | awk 'NR==2{gsub(/^\s+|\s*\/\/.*$/,"");split($0,a,","); for(i in a){gsub(/^["\s]+|["\s]+$/,"",a[i]);printf "%s ",a[i]}}')
            [[ -n "$result" ]] && remove_spaces_and_quotes "$result"
          else
            grep -aPoz "\"realitySettings\":\s*\{[^}]*\}" "$CONFIG_PATH" | grep -aPo "\"$list_field\":\s*\"[^\"]*\"" | head -n1 | sed -E "s/\"$list_field\":\s*\"([^\"]*)\"/\1/"
          fi
        }
        get_public_ip() { fetch "https://api.ipify.org" || fetch "https://api64.ipify.org" || echo "127.0.0.1"; }

        $SUDO systemctl restart xray || true
        sleep 2
        if ! systemctl is-active --quiet xray; then
          cecho "$RED" "未能启动 xray 服务，请检查日志。"; systemctl status xray --no-pager
        else
          cecho "$GREEN" "xray 已启动！"
          local UUID PORT TLS SERVER_NAME SHORT_IDS SNI ADDRESS FLOW SID PBK
          UUID="$(grep -aPoz '"clients":\s*\[\s*\{[^}]*\}\s*\]' "$CONFIG_PATH" | grep -aPo '"id":\s*"[^\"]*"' | head -n1 | cut -d'"' -f4)"
          PORT="$(extract_field "port" "\d+")"
          TLS="$(extract_field "security" "\"[^\"]*\"")"
          SERVER_NAME="$(extract_server_name)"
          SHORT_IDS="$(extract_list_field "realitySettings" "shortIds" || true)"
          SNI="${SERVER_NAME:-your.domain.net}"
          ADDRESS="$(get_public_ip)"
          PORT="${PORT:-443}"
          FLOW="$(extract_field "flow" "\"[^\"]*\"")"
          SID="${SHORT_IDS:-}"
          PBK="${PUBLIC_KEY:-}"
          local vless_uri="vless://${UUID}@${ADDRESS}:${PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${SNI}&fp=chrome&pbk=${PBK}&sid=${SID}&type=tcp&headerType=none#Xray"
          echo "VLESS 链接如下："
          cecho "$BLUE" "$vless_uri"
        fi
        pause
        ;;
      "")
        return
        ;;
      *)
        cecho "$RED" "无效选项，请重新输入。"
        ;;
    esac
  done
}

# ----------------------------[ Hysteria2 ]----------------------------
install_hysteria2() {
  while true; do
    echo "========================================="
    echo -e "           ${BOLD}${GREEN}安装Hysteria2${RESET}  "
    echo "========================================="
    echo "1) 安装升级"
    echo "2) 编辑配置"
    echo "3) 重启服务"
    echo "4) 端口跳跃"
    echo "5) 卸载服务"
    echo "========================================="
    read -r -p "请输入数字 [1-5] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1)
        if bash <(fetch "https://get.hy2.sh") && $SUDO systemctl enable --now hysteria-server.service; then
          sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1 || true
          sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1 || true
          cecho "$GREEN" "hysteria2 安装升级完成！"
        else
          cecho "$RED" "hysteria2 安装升级失败！"
        fi
        pause
        ;;
      2)
        cecho "$YELLOW" "提示：将域名填入配置文件中。"
        pause
        ensure_pkg nano
        $SUDO nano /etc/hysteria/config.yaml
        pause
        ;;
      3)
        local config_file="/etc/hysteria/config.yaml"
        get_domain_from_cert() {
          local cert="$1"
          openssl x509 -in "$cert" -text -noout 2>/dev/null | grep -Po "DNS:[^,]*" | head -n1 | sed 's/DNS://' \
            || openssl x509 -in "$cert" -text -noout 2>/dev/null | grep -Po "CN=[^ ]*" | sed 's/CN=//'
        }
        get_ip_address() {
          local ip
          ip=$(fetch "https://ifconfig.me" 2>/dev/null || true)
          if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then echo "$ip"; return 0; fi
          ip=$(fetch "https://ifconfig.me" 2>/dev/null || true)
          if [[ "$ip" =~ ^[0-9A-Fa-f:]+$ ]]; then echo "[$ip]"; return 0; fi
          return 1
        }
        if [[ ! -f "$config_file" ]]; then cecho "$RED" "未能找到配置文件。"; pause; return; fi
        $SUDO systemctl restart hysteria-server.service || true
        sleep 2
        if ! systemctl is-active --quiet hysteria-server.service; then
          cecho "$RED" "未能启动 hysteria 服务，请检查日志。"
          $SUDO systemctl status hysteria-server.service --no-pager
          pause; return
        else
          cecho "$GREEN" "hysteria 已启动！"
        fi
        local port password domain cert_path ip
        port="$(awk -F: '/^listen:/{print $3}' "$config_file" | tr -d ' ' || true)"; port="${port:-443}"
        password="$(awk '/^[[:space:]]*password:/{print $2}' "$config_file" | head -n1 || true)"
        domain="$(awk '/domains:/{getline; gsub(/[ -]/,""); print}' "$config_file" || true)"
        if [[ -z "${domain:-}" ]]; then
          cert_path="$(awk -F': ' '/cert:/{print $2}' "$config_file" | tr -d '"' | head -n1)"
          [[ -n "$cert_path" && -f "$cert_path" ]] && domain="$(get_domain_from_cert "$cert_path" || true)"
        fi
        ip="$(get_ip_address || true)"
        if [[ -z "${ip:-}" || -z "${domain:-}" || -z "${password:-}" ]]; then
          cecho "$RED" "生成链接所需信息不足（IP/域名/密码）。"
        else
          local uri="hysteria2://${password}@${ip}:${port}?sni=${domain}&insecure=0#hysteria"
          echo "hysteria2 链接如下："; cecho "$BLUE" "$uri"
        fi
        pause
        ;;
      4)
        local default_redirect_port=443
        local default_start_port=60000
        local default_end_port=65535
        local config_file="/etc/hysteria/config.yaml"
        local redirect_port
        if [[ -f "$config_file" ]]; then
          redirect_port="$(awk -F: '/listen:/{print $NF}' "$config_file" | tr -d ' ')"
        fi
        [[ -z "$redirect_port" || ! "$redirect_port" =~ ^[0-9]+$ || "$redirect_port" -lt 1 || "$redirect_port" -gt 65535 ]] && redirect_port="$default_redirect_port"
        read -r -p "请输入起始端口号 (默认 60000): " start_port; start_port="${start_port:-$default_start_port}"
        if ! [[ "$start_port" =~ ^[0-9]+$ ]] || (( start_port<1 || start_port>65535 )); then cecho "$RED" "起始端口无效，使用默认 60000"; start_port="$default_start_port"; fi
        read -r -p "请输入结束端口号 (默认 65535): " end_port; end_port="${end_port:-$default_end_port}"
        if ! [[ "$end_port" =~ ^[0-9]+$ ]] || (( end_port<start_port || end_port>65535 )); then cecho "$RED" "结束端口无效，使用默认 65535"; end_port="$default_end_port"; fi
        local iface; iface="$(default_iface || true)"; [[ -z "$iface" ]] && iface="$(ip -o link | awk -F': ' '$2!="lo"{print $2; exit}')"
        if [[ -z "$iface" ]]; then cecho "$RED" "未找到网络接口，无法执行 iptables。"; pause; return; fi
        if $SUDO iptables -t nat -A PREROUTING -i "$iface" -p udp --dport "$start_port:$end_port" -j REDIRECT --to-ports "$redirect_port"; then
          cecho "$GREEN" "端口跳跃设置成功!"
        else
          cecho "$RED" "iptables 命令执行失败。"
        fi
        pause
        ;;
      5)
        if bash <(fetch "https://get.hy2.sh") --remove && \
           $SUDO rm -rf /etc/hysteria && \
           $SUDO userdel -r hysteria 2>/dev/null || true && \
           $SUDO rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service && \
           $SUDO systemctl daemon-reload
        then
          cecho "$GREEN" "hysteria2 已卸载。"
        fi
        pause
        ;;
      "")
        return
        ;;
      *)
        cecho "$RED" "无效选项，请重新输入。"
        ;;
    esac
  done
}

# ----------------------------[ sing-box ]----------------------------
install_sing-box() {
  while true; do
    echo "========================================="
    echo -e "           ${BOLD}${GREEN}安装sing-box${RESET}  "
    echo "========================================="
    echo "1) 安装升级"
    echo "2) 编辑配置"
    echo "3) 重启服务"
    echo "4) 卸载服务"
    echo "========================================="
    read -r -p "请输入数字 [1-4] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1)
        if bash <(fetch "https://sing-box.app/deb-install.sh") && \
           fetch "https://raw.githubusercontent.com/sezhai/VPS-Script/refs/heads/main/extras/sing-box/config.json" "/etc/sing-box/config.json"
        then
          cecho "$GREEN" "sing-box 安装升级成功！"
          echo "以下是 UUID："; cecho "$BLUE" "$(sing-box generate uuid)"
          local keys PRIVATE_KEY PUBLIC_KEY
          keys="$(sing-box generate reality-keypair)"
          PRIVATE_KEY="$(awk '/PrivateKey/{print $2}' <<<"$keys")"
          PUBLIC_KEY="$(awk '/PublicKey/{print $2}' <<<"$keys")"
          export PRIVATE_KEY PUBLIC_KEY
          echo "以下是私钥："; cecho "$BLUE" "$PRIVATE_KEY"
          echo "以下是 ShortIds："; cecho "$BLUE" "$(sing-box generate rand 8 --hex)"
        else
          cecho "$RED" "sing-box 安装升级失败！"
        fi
        pause
        ;;
      2)
        cecho "$YELLOW" "提示：根据提示修改配置文件。"
        pause
        ensure_pkg nano
        $SUDO nano /etc/sing-box/config.json
        pause
        ;;
      3)
        local CONFIG_PATH="/etc/sing-box/config.json"
        $SUDO systemctl restart sing-box || true
        sleep 2
        if ! systemctl is-active --quiet sing-box; then
          cecho "$RED" "未能启动 sing-box 服务，请检查日志。"
          systemctl status sing-box --no-pager
          pause; return
        else
          cecho "$GREEN" "sing-box 已启动！"
        fi
        get_ip() {
          fetch "https://api.ipify.org" || fetch "https://icanhazip.com" | tr -d '\n' || fetch "https://api6.ipify.org" || fetch "https://icanhazip.com" || echo "127.0.0.1"
        }
        urlencode() { local s="$1" ch; for ((i=0;i<${#s};i++)); do ch="${s:i:1}"; case "$ch" in [a-zA-Z0-9.~_-]) printf '%s' "$ch";; *) printf '%%%02X' "'$ch";; esac; done; }
        get_domain_from_cert() {
          openssl x509 -in "$1" -text -noout 2>/dev/null | grep -Po "DNS:[^,]*" | head -n1 | sed 's/DNS://' \
            || openssl x509 -in "$1" -text -noout 2>/dev/null | grep -Po "CN=[^ ]*" | sed 's/CN=//'
        }
        local ip ip_for_url
        ip="$(get_ip)"; ip_for_url="$ip"
        if [[ "$ip" =~ : ]] && [[ "$ip" != "127.0.0.1" ]]; then ip_for_url="[$ip]"; fi

        if grep -q '"tag":\s*"vmess"' "$CONFIG_PATH"; then
          local vmess_uuid vmess_port vmess_path vmess_host
          vmess_uuid="$(grep -A 20 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"uuid":\s*"[^"]*"' | head -1 | cut -d'"' -f4)"
          vmess_port="$(grep -A 5 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')"
          vmess_path="$(grep -A 30 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"path":\s*"[^"]*"' | cut -d'"' -f4)"
          vmess_host="$(grep -A 30 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"server_name":\s*"[^"]*"' | cut -d'"' -f4)"
          if [[ -n "$vmess_uuid" && -n "$vmess_port" ]]; then
            local vmess_json
            vmess_json='{"v":"2","ps":"vmess","add":"'"$ip"'","port":"'"$vmess_port"'","id":"'"$vmess_uuid"'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'"$vmess_host"'","path":"'"$vmess_path"'","tls":"tls","sni":"'"$vmess_host"'","alpn":"http/1.1","fp":"chrome"}'
            echo "vmess 链接如下："; cecho "$BLUE" "vmess://$(echo -n "$vmess_json" | base64 -w0)"
          fi
        fi
        if grep -q '"tag":\s*"reality"' "$CONFIG_PATH"; then
          local vless_uuid vless_port vless_sni vless_sid
          vless_uuid="$(grep -A 20 '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"uuid":\s*"[^"]*"' | head -1 | cut -d'"' -f4)"
          vless_port="$(grep -A 5 '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')"
          vless_sni="$(grep -A 30 '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"server_name":\s*"[^"]*"' | head -1 | cut -d'"' -f4)"
          vless_sid="$(grep -A 30 '"tag":\s*"reality"' "$CONFIG_PATH" | sed -n '/"short_id"/,/]/p' | grep -o '"[a-fA-F0-9]*"' | head -1 | tr -d '"')"
          if [[ -n "$vless_uuid" && -n "$vless_port" ]]; then
            local link="vless://$vless_uuid@$ip_for_url:$vless_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vless_sni&fp=chrome&pbk=$PUBLIC_KEY&sid=$vless_sid&type=tcp&headerType=none#reality"
            echo "reality 链接如下："; cecho "$BLUE" "$link"
          fi
        fi
        if grep -q '"tag":\s*"hysteria2"' "$CONFIG_PATH"; then
          local h2_pass h2_port cert_path h2_domain
          h2_pass="$(grep -A 20 '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"password":\s*"[^"]*"' | cut -d'"' -f4)"
          h2_port="$(grep -A 5 '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')"
          cert_path="$(grep -A 30 '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"certificate_path":\s*"[^"]*"' | cut -d'"' -f4)"
          if [[ -n "$h2_pass" && -n "$h2_port" && -f "$cert_path" ]]; then
            h2_domain="$(get_domain_from_cert "$cert_path" || true)"
            if [[ -n "$h2_domain" ]]; then
              echo "hysteria2 链接如下："
              cecho "$BLUE" "hysteria2://$(urlencode "$h2_pass")@$ip_for_url:$h2_port?sni=$h2_domain&insecure=0#hysteria2"
            fi
          fi
        fi
        pause
        ;;
      4)
        if $SUDO systemctl disable --now sing-box && $SUDO rm -f /usr/local/bin/sing-box /etc/systemd/system/sing-box.service && \
           $SUDO rm -rf /var/lib/sing-box /etc/sing-box; then
          cecho "$GREEN" "sing-box 已卸载。"
        fi
        pause
        ;;
      "")
        return
        ;;
      *)
        cecho "$RED" "无效选项，请重新输入。"
        ;;
    esac
  done
}

# ----------------------------[ 1Panel ]----------------------------
install_1panel() {
  while true; do
    echo "========================================="
    echo -e "               ${BOLD}${GREEN}安装1Panel${RESET} "
    echo "========================================="
    echo "1) 安装面板"
    echo "2) 查看信息"
    echo "3) 安装防火墙"
    echo "4) 卸载防火墙"
    echo "5) 卸载面板"
    echo "========================================="
    read -r -p "请输入数字 [1-5] 选择 (默认回车退出)：" sub
    case "${sub:-}" in
      1)
        if fetch "https://resource.fit2cloud.com/1panel/package/quick_start.sh" "quick_start.sh" && $SUDO bash quick_start.sh; then
          cecho "$GREEN" "1Panel 安装完成！"
        else
          cecho "$RED" "1Panel 安装失败！"
        fi
        pause
        ;;
      2)
        1pctl user-info || cecho "$RED" "无法获取 1Panel 信息。"
        pause
        ;;
      3)
        ensure_pkg ufw; cecho "$GREEN" "ufw 安装完成！"
        pause
        ;;
      4)
        if $SUDO apt-get remove -y ufw && $SUDO apt-get purge -y ufw && $SUDO apt-get autoremove -y; then
          cecho "$GREEN" "ufw 卸载完成。"
        else
          cecho "$RED" "ufw 卸载失败！"
        fi
        pause
        ;;
      5)
        if $SUDO systemctl stop 1panel 2>/dev/null || true && \
           $SUDO 1pctl uninstall 2>/dev/null || true && \
           $SUDO rm -rf /var/lib/1panel /etc/1panel /usr/local/bin/1pctl && \
           $SUDO journalctl --vacuum-time=3d && \
           $SUDO systemctl stop docker 2>/dev/null || true && \
           $SUDO apt-get purge -y docker-ce docker-ce-cli containerd.io 2>/dev/null || true && \
           $SUDO find / \( -name "1panel*" -o -name "docker*" -o -name "containerd*" -o -name "compose*" \) -exec rm -rf {} + 2>/dev/null || true && \
           $SUDO groupdel docker 2>/dev/null || true
        then
          cecho "$GREEN" "1Panel 卸载完成。"
        fi
        pause
        ;;
      "")
        return
        ;;
      *)
        cecho "$RED" "无效选项，请重新输入。"
        ;;
    esac
  done
}

# ----------------------------[ 主循环 ]----------------------------
while true; do
  display_main_menu
  read -r -p "请输入数字 [1-9] 选择(默认回车退出)：" choice
  case "${choice:-}" in
    "") cecho "$GREEN" "退出脚本，感谢使用！"; exit 0 ;;
    1) view_vps_info ;;
    2) display_system_optimization_menu ;;
    3) common_tools ;;
    4) install_package ;;
    5) apply_certificate ;;
    6) install_xray ;;
    7) install_hysteria2 ;;
    8) install_sing-box ;;
    9) install_1panel ;;
    *) cecho "$RED" "无效选项，请输入数字 1-9 或直接回车退出！" ;;
  esac
done
