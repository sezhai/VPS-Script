#!/usr/bin/env bash
# VPS 管理脚本

# ------------------------- 公共初始化 -------------------------
# 统一 sudo
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo -e "\e[31m本脚本需要 root 权限或已安装 sudo。\e[0m"
    exit 1
  fi
fi

# root 且系统无 sudo 时，注入一次性 sudo shim（修复外部脚本内部 sudo 报错）
if [ -z "$SUDO" ] && ! command -v sudo >/dev/null 2>&1; then
  _SUDO_SHIM_DIR="/tmp/.sudo_shim_$$"
  mkdir -p "$_SUDO_SHIM_DIR"
  cat >"$_SUDO_SHIM_DIR/sudo" <<'EOF'
#!/bin/sh
# 简单 sudo 替身：直接执行后续命令
exec "$@"
EOF
  chmod +x "$_SUDO_SHIM_DIR/sudo"
  export PATH="$_SUDO_SHIM_DIR:$PATH"
fi

# 统一“按任意键返回”
pause() { read -n 1 -s -r -p "按任意键返回..."; echo; }

# 确保有可用编辑器（原脚本约定使用 nano，不加功能，仅保证可用）
need_editor() {
  if ! command -v nano >/dev/null 2>&1; then
    $SUDO apt update >/dev/null 2>&1 && $SUDO apt install -y nano >/dev/null 2>&1 || {
      echo -e "\e[31m错误：无法安装或找到 nano！\e[0m"; return 1;
    }
  fi
  return 0
}

# 下载到临时文件再执行，避免 bash -c 参数传递歧义
curl_exec() {
  # 用法：curl_exec URL [args...]
  local url="$1"; shift || true
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$url" -o "$tmp" || { echo -e "\e[31m下载失败：$url\e[0m"; rm -f "$tmp"; return 1; }
  chmod +x "$tmp"
  bash "$tmp" "$@"
  local rc=$?
  rm -f "$tmp"
  return $rc
}

# 公共：取公网 IP（优先 IPv4，退化 IPv6）
get_public_ip() {
  local ipv4 ipv6
  ipv4="$(curl -fsS -4 https://api.ipify.org 2>/dev/null || true)"
  if [ -n "$ipv4" ]; then echo "$ipv4"; return 0; fi
  ipv6="$(curl -fsS -6 https://api64.ipify.org 2>/dev/null || true)"
  if [ -n "$ipv6" ]; then echo "$ipv6"; return 0; fi
  echo "127.0.0.1"
}

# 公共：从证书获取域名
get_domain_from_cert() {
  # 用法：get_domain_from_cert /path/to/cert.crt
  local cert="$1"
  openssl x509 -in "$cert" -text -noout 2>/dev/null | grep -aPo "DNS:[^,]*" | sed 's/DNS://' | head -n 1 ||
  openssl x509 -in "$cert" -text -noout 2>/dev/null | grep -aPo "CN=[^ ,]*" | sed 's/CN=//' || true
}

# ------------------------- 主菜单 -------------------------
display_main_menu() {
  clear
  echo "========================================="
  echo -e "               \e[1;96mVPS管理脚本\e[0m"
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

# ------------------------- 系统信息 -------------------------
view_vps_info() {
  echo -e "\e[1;34m主机名:\e[0m \e[32m$(hostname)\e[0m"
  echo -e "\e[1;34m系统版本:\e[0m \e[32m$(
    lsb_release -ds 2>/dev/null || awk -F= '/^PRETTY_NAME=/{gsub(/"/,"");print $2}' /etc/os-release
  )\e[0m"
  echo -e "\e[1;34mLinux版本:\e[0m \e[32m$(uname -r)\e[0m"
  echo "-------------"
  echo -e "\e[1;34mCPU架构:\e[0m \e[32m$(uname -m)\e[0m"
  echo -e "\e[1;34mCPU型号:\e[0m \e[32m$(lscpu | awk -F: '/Model name/{sub(/^ +/,"",$2);print $2}')\e[0m"
  echo -e "\e[1;34mCPU核心数:\e[0m \e[32m$(nproc)\e[0m"
  echo -e "\e[1;34mCPU频率:\e[0m \e[32m$(lscpu | awk -F: '/CPU MHz/{gsub(/^ +/,"",$2);print $2}') MHz\e[0m"
  echo "-------------"
  echo -e "\e[1;34mCPU占用:\e[0m \e[32m$(top -bn1 | awk -F'[, ]+' '/Cpu\(s\)/{print $2+$4}')%\e[0m"
  echo -e "\e[1;34m系统负载:\e[0m \e[32m$(awk '{print $1, $2, $3}' /proc/loadavg)\e[0m"
  local mem_info; mem_info=$(free -m | awk '/Mem:/ {printf "%.2f/%.2f MB (%.2f%%)", $3,$2,$3*100/$2}')
  local swap_info; swap_info=$(free -m | awk '/Swap:/ {if($2>0) printf "%.0fMB/%.0fMB (%.0f%%)",$3,$2,$3*100/$2; else print "数据不可用"}')
  echo -e "\e[1;34m物理内存:\e[0m \e[32m${mem_info}\e[0m"
  echo -e "\e[1;34m虚拟内存:\e[0m \e[32m${swap_info}\e[0m"
  echo -e "\e[1;34m硬盘占用:\e[0m \e[32m$(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')\e[0m"
  echo "-------------"
  local NET_INTERFACE; NET_INTERFACE=$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')
  if [ -n "$NET_INTERFACE" ]; then
    local RX_BYTES TX_BYTES RX_MB TX_MB
    RX_BYTES=$(cat /sys/class/net/$NET_INTERFACE/statistics/rx_bytes)
    TX_BYTES=$(cat /sys/class/net/$NET_INTERFACE/statistics/tx_bytes)
    RX_MB=$(awk "BEGIN{printf \"%.2f\", $RX_BYTES/1048576}")
    TX_MB=$(awk "BEGIN{printf \"%.2f\", $TX_BYTES/1048576}")
    echo -e "\e[1;34m网络接口:\e[0m \e[32m$NET_INTERFACE\e[0m"
    echo -e "\e[1;34m总接收:\e[0m \e[32m${RX_MB} MB\e[0m"
    echo -e "\e[1;34m总发送:\e[0m \e[32m${TX_MB} MB\e[0m"
  else
    echo -e "\e[31m未检测到有效的网络接口！\e[0m"
  fi
  echo "-------------"
  if [ -f /proc/sys/net/ipv4/tcp_congestion_control ]; then
    echo -e "\e[1;34m网络算法:\e[0m \e[32m$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')\e[0m"
  else
    echo -e "\e[1;34m网络算法:\e[0m \e[31mIPv4 未启用或不支持。\e[0m"
  fi
  echo "-------------"
  echo -e "\e[1;34m运营商:\e[0m \e[32m$(curl -fsS ipinfo.io/org | sed 's/^ *//;s/ *$//')\e[0m"
  echo -e "\e[1;34mIPv4地址:\e[0m \e[32m$(curl -fsS ipv4.icanhazip.com)\e[0m"
  echo -e "\e[1;34mIPv6地址:\e[0m \e[32m$(ip -6 addr show scope global | awk '/inet6/&&!/temporary|tentative/{print $2}' | cut -d/ -f1 | head -n1 | ( grep . || echo '未检测到IPv6地址' ))\e[0m"
  echo -e "\e[1;34mDNS地址:\e[0m \e[32m$(awk '/^nameserver/{print $2}' /etc/resolv.conf | xargs | sed 's/ /, /g')\e[0m"
  echo -e "\e[1;34m地理位置:\e[0m \e[32m$(curl -fsS ipinfo.io/city), $(curl -fsS ipinfo.io/country)\e[0m"
  echo -e "\e[1;34m系统时间:\e[0m \e[32m$(timedatectl | awk -F'[: ]+' '/Local time/{print $4, $5, $6}')\e[0m"
  echo -e "\e[1;34m运行时长:\e[0m \e[32m$(uptime -p | sed 's/^up //')\e[0m"
  pause
}

# ------------------------- 系统优化 -------------------------
display_system_optimization_menu() {
  while true; do
    echo "========================================="
    echo -e "               \e[1;32m系统优化\e[0m"
    echo "========================================="
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
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

calibrate_time() {
  echo -e "\n[校准时间]"
  $SUDO timedatectl set-timezone Asia/Shanghai
  $SUDO timedatectl set-ntp true
  echo -e "\e[32m时间校准完成，当前时区为 Asia/Shanghai。\e[0m"
  pause
}

update_system() {
  echo -e "\n[更新系统]"
  if $SUDO apt update -y && $SUDO apt full-upgrade -y; then
    $SUDO apt autoremove -y && $SUDO apt autoclean -y
    echo -e "\e[32m系统更新完成！\e[0m"
  else
    echo -e "\e[31m系统更新失败！请检查网络连接或源列表。\e[0m"
  fi
  pause
}

clean_system() {
  echo -e "\n[清理系统]"
  $SUDO apt autoremove --purge -y
  $SUDO apt clean -y && $SUDO apt autoclean -y
  $SUDO journalctl --rotate || true
  $SUDO journalctl --vacuum-time=10m || true
  $SUDO journalctl --vacuum-size=50M || true
  echo -e "\e[32m系统清理完成！\e[0m"
  pause
}

enable_bbr() {
  echo -e "\n[开启BBR]"
  if sysctl net.ipv4.tcp_congestion_control | grep -q 'bbr'; then
    echo -e "\e[32mBBR已开启！\e[0m"
  else
    echo "net.core.default_qdisc = fq" | $SUDO tee -a /etc/sysctl.conf >/dev/null
    echo "net.ipv4.tcp_congestion_control = bbr" | $SUDO tee -a /etc/sysctl.conf >/dev/null
    if $SUDO sysctl -p; then
      echo -e "\e[32mBBR已开启！\e[0m"
    else
      echo -e "\e[31mBBR 开启失败！\e[0m"
    fi
  fi
  pause
}

root_login() {
  while true; do
    echo "========================================="
    echo -e "               \e[1;34mROOT登录\e[0m"
    echo "========================================="
    echo "1) 设置密码"
    echo "2) 修改配置"
    echo "3) 重启服务"
    echo "========================================="
    read -p "请输入数字 [1-3] 选择 (默认回车退出)：" root_choice
    case "$root_choice" in
      1) $SUDO passwd root; pause ;;
      2)
        $SUDO sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
        $SUDO sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
        echo -e "\e[32m配置修改成功！\e[0m"; pause ;;
      3)
        if $SUDO systemctl restart sshd.service; then
          echo -e "\e[32mROOT登录已开启！\e[0m"
        else
          echo -e "\e[31mROOT登录开启失败！\e[0m"
        fi
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

user_sysinit() {
  set -e
  read -p "$(echo -e '\033[0;31m输入y继续（默认回车退出）:\033[0m ') " confirm
  [[ "$confirm" != "y" ]] && { set +e; return 0; }

  echo -e "\033[0;34m[INFO]\033[0m 清理后装应用文件..."
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
    [ -e "$path" ] && rm -rf "$path" 2>/dev/null && echo -e "\033[0;34m[INFO]\033[0m 删除: $path"
  done

  echo -e "\033[0;34m[INFO]\033[0m 清理后装 systemd 服务..."
  local CLEANUP_SERVICES=(
    "xray" "v2ray" "sing-box" "hysteria" "hysteria2" "hy2"
    "clash" "trojan" "caddy" "frps" "frpc" "1panel"
    "nezha-agent" "nezha-dashboard" "aria2" "filebrowser"
    "portainer" "docker" "containerd"
  )
  for service in "${CLEANUP_SERVICES[@]}"; do
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service}.service" \
          "/etc/systemd/system/${service}d.service" \
          "/etc/systemd/system/${service}-agent.service" \
          "/etc/systemd/system/${service}-dashboard.service"
  done
  systemctl daemon-reload 2>/dev/null || true

  echo -e "\033[0;34m[INFO]\033[0m 终止后装应用进程..."
  local KILL_PATTERNS=( xray v2ray sing-box hysteria clash trojan caddy frps frpc 1panel nezha aria2 filebrowser portainer docker containerd )
  for pattern in "${KILL_PATTERNS[@]}"; do pkill -f "$pattern" 2>/dev/null || true; done

  echo -e "\033[0;34m[INFO]\033[0m 删除后装 APT 包..."
  local REMOVE_PKGS=(docker.io docker-ce docker-compose containerd.io docker-compose-plugin)
  for pkg in "${REMOVE_PKGS[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
      echo -e "\033[0;34m[INFO]\033[0m 删除APT包: $pkg"
      apt remove --purge -y "$pkg" -qq 2>/dev/null || true
    fi
  done

  echo -e "\033[0;34m[INFO]\033[0m 清理用户目录..."
  for home in /home/*/; do
    [ -d "$home" ] || continue
    rm -rf "${home}.config/1panel" "${home}.config/clash" "${home}.config/v2ray" \
           "${home}.xray" "${home}.v2ray" 2>/dev/null || true
  done

  echo -e "\033[0;34m[INFO]\033[0m 清理缓存..."
  rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
  apt autoclean -y >/dev/null 2>&1 || true
  apt clean -y >/dev/null 2>&1 || true

  echo -e "\033[0;34m[INFO]\033[0m 验证系统完整性..."
  dpkg --configure -a --force-confold 2>/dev/null || true
  apt update -qq 2>/dev/null || { apt install -f -y -qq 2>/dev/null || true; apt update -qq 2>/dev/null || true; }

  for service in systemd-resolved systemd-networkd networking; do
    systemctl is-enabled "$service" >/dev/null 2>&1 && systemctl restart "$service" 2>/dev/null || true
  done

  echo -e "\e[32m系统初始化完成！\e[0m"
  read -p "$(echo -e '\033[0;31m输入y重启系统（默认回车退出）:\033[0m ') " reboot_choice
  [[ "$reboot_choice" == "y" ]] && $SUDO reboot
  set +e
  pause
}

# ------------------------- 常用工具 -------------------------
common_tools() {
  while true; do
    echo "========================================="
    echo -e "               \e[1;32m常用工具\e[0m"
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
    read -p "请输入数字 [1-8] 选择 (默认回车退出)：" root_choice
    case "$root_choice" in
      1)
        read -p "请输入要查找的文件名: " filename
        if [ -z "$filename" ]; then
          echo -e "\e[31m文件名不能为空。\e[0m"
        else
          find / -type f -name "*$filename*" 2>/dev/null || echo -e "\e[31m未找到匹配的文件。\e[0m"
        fi
        pause ;;
      2)
        read -p "请输入文件路径: " file_path
        if [ ! -e "$file_path" ]; then echo -e "\e[31m错误: '$file_path' 不存在。\e[0m"; else
          chmod 755 "$file_path" && echo -e "\e[32m'$file_path' 权限已设置为 755！\e[0m" || echo -e "\e[31m设置失败。\e[0m"
        fi
        pause ;;
      3)
        while true; do
          read -p "请输入要删除的文件或目录名（默认回车退出）: " filename
          [ -z "$filename" ] && break
          mapfile -t files < <(find / \( -type f -o -type d \) -iname "*$filename*" 2>/dev/null)
          if [ "${#files[@]}" -eq 0 ]; then echo -e "\e[31m未找到匹配。\e[0m"; continue; fi
          echo "找到以下文件或目录:"; for i in "${!files[@]}"; do echo "$((i+1)). ${files[$i]}"; done
          read -p "输入要删除的编号（可多选，空格分隔，回车取消）: " choices
          [ -z "$choices" ] && { echo "取消删除。"; continue; }
          for choice in $choices; do
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
              file="${files[$((choice-1))]}"
              read -p "确定要删除 $file 吗？(y/n): " confirm
              if [ "$confirm" = "y" ]; then
                [ -d "$file" ] && rm -rf "$file" || rm -f "$file"
                echo -e "\e[32m已删除: $file\e[0m"
              else
                echo "取消：$file"
              fi
            else
              echo -e "\e[31m无效编号: $choice\e[0m"
            fi
          done
        done
        pause ;;
      4) ps aux; pause ;;
      5)
        while true; do
          read -p "请输入要关闭的进程 PID: " pid
          if [[ "$pid" =~ ^[0-9]+$ ]]; then
            if kill "$pid" 2>/dev/null; then
              echo -e "\e[32m进程 $pid 已关闭（SIGTERM）。\e[0m"
            else
              echo -e "\e[31m无法正常关闭，是否强制 (SIGKILL)？ (y/n)\e[0m"
              read -p "请选择 (y/n): " c; [ "$c" = "y" ] && kill -9 "$pid" && echo -e "\e[32m已强制关闭 $pid。\e[0m" || echo "已取消。"
            fi; break
          else
            echo -e "\e[31m无效 PID。\e[0m"
          fi
        done
        pause ;;
      6)
        echo -e "端口     类型    程序名               PID"
        if command -v ss >/dev/null 2>&1; then
          ss -tulnp | awk 'NR>1{split($5,a,":");split($7,b,",");gsub(/[()]/,"",b[1]);gsub(/pid=/,"",b[2]);gsub(/users:/,"",b[1]);gsub(/"/,"",b[1]); if(a[2]!=""&&a[2]!="*") printf "%-8s %-7s %-20s %-6s\n",a[2],$1,b[1],b[2]}'
        else
          netstat -tulnp | awk 'NR>2{split($4,a,":");split($7,b,"/");gsub(/[()]/,"",b[1]);gsub(/pid=/,"",b[2]);gsub(/users:/,"",b[1]);gsub(/"/,"",b[1]); if(a[2]!=""&&a[2]!="*") printf "%-8s %-7s %-20s %-6s\n",a[2],$1,b[1],b[2]}'
        fi
        pause ;;
      7)
        while true; do
          echo "请选择协议: 1) TCP  2) UDP"
          read -p "请输入1或2: " protocol_choice
          case "$protocol_choice" in
            1) protocol="tcp" ;;
            2) protocol="udp" ;;
            *) echo -e "\e[31m无效选择。\e[0m"; break ;;
          esac
          read -p "请输入端口号: " port
          if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            echo -e "\e[31m无效端口。\e[0m"; break
          fi
          if $SUDO iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT; then
            echo -e "\e[32m端口 $port 已开放（$protocol）。\e[0m"
          else
            echo -e "\e[31m执行失败。\e[0m"
          fi
          break
        done
        pause ;;
      8)
        if ! command -v speedtest-cli >/dev/null 2>&1; then
          echo "未检测到 speedtest-cli，正在安装..."
          $SUDO apt update && $SUDO apt install -y speedtest-cli
        else
          echo "已安装 speedtest-cli，直接测速..."
        fi
        echo "开始测速..."
        speedtest-cli
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

# ------------------------- 常用软件包 -------------------------
install_package() {
  while true; do
    echo "========================================="
    echo -e "               \e[1;32m常用软件包\e[0m"
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
    read -p "请输入数字 [1-9] 选择 (默认回车退出)：" opt_choice
    case "$opt_choice" in
      1) if $SUDO apt update; then echo -e "\e[32mapt 更新完成！\e[0m"; else echo -e "\e[31mapt 更新失败！\e[0m"; fi; pause ;;
      2)
        echo "1) 安装  2) 卸载"; read -p "请选择操作：" action
        case "$action" in
          1) if apt update && apt install -y sudo; then echo -e "\e[32msudo 安装完成！\e[0m"; else echo -e "\e[31msudo 安装失败！\e[0m"; fi ;;
          2) if $SUDO apt remove -y sudo; then echo -e "\e[32msudo 卸载完成！\e[0m"; else echo -e "\e[31msudo 卸载失败！\e[0m"; fi ;;
        esac; pause ;;
      3)
        echo "1) 安装  2) 卸载"; read -p "请选择操作：" action
        case "$action" in
          1) if $SUDO apt update && $SUDO apt install -y wget; then echo -e "\e[32mwget 安装完成！\e[0m"; else echo -e "\e[31mwget 安装失败！\e[0m"; fi ;;
          2) if $SUDO apt remove -y wget; then echo -e "\e[32mwget 卸载完成！\e[0m"; else echo -e "\e[31mwget 卸载失败！\e[0m"; fi ;;
        esac; pause ;;
      4)
        echo "1) 安装  2) 卸载"; read -p "请选择操作：" action
        case "$action" in
          1) if $SUDO apt update && $SUDO apt install -y nano; then echo -e "\e[32mnano 安装完成！\e[0m"; else echo -e "\e[31mnano 安装失败！\e[0m"; fi ;;
          2) if $SUDO apt remove -y nano; then echo -e "\e[32mnano 卸载完成！\e[0m"; else echo -e "\e[31mnano 卸载失败！\e[0m"; fi ;;
        esac; pause ;;
      5)
        echo "1) 安装  2) 卸载"; read -p "请选择操作：" action
        case "$action" in
          1) if $SUDO apt update && $SUDO apt install -y vim; then echo -e "\e[32mvim 安装完成！\e[0m"; else echo -e "\e[31mvim 安装失败！\e[0m"; fi ;;
          2) if $SUDO apt remove -y vim; then echo -e "\e[32mvim 卸载完成！\e[0m"; else echo -e "\e[31mvim 卸载失败！\e[0m"; fi ;;
        esac; pause ;;
      6)
        echo "1) 安装  2) 卸载"; read -p "请选择操作：" action
        case "$action" in
          1) if $SUDO apt update && $SUDO apt install -y zip; then echo -e "\e[32mzip 安装完成！\e[0m"; else echo -e "\e[31mzip 安装失败！\e[0m"; fi ;;
          2) if $SUDO apt remove -y zip; then echo -e "\e[32mzip 卸载完成！\e[0m"; else echo -e "\e[31mzip 卸载失败！\e[0m"; fi ;;
        esac; pause ;;
      7)
        echo "1) 安装  2) 卸载"; read -p "请选择操作：" action
        case "$action" in
          1) if $SUDO apt update && $SUDO apt install -y git; then echo -e "\e[32mgit 安装完成！\e[0m"; else echo -e "\e[31mgit 安装失败！\e[0m"; fi ;;
          2) if $SUDO apt remove -y git; then echo -e "\e[32mgit 卸载完成！\e[0m"; else echo -e "\e[31mgit 卸载失败！\e[0m"; fi ;;
        esac; pause ;;
      8)
        echo "1) 安装  2) 卸载"; read -p "请选择操作：" action
        case "$action" in
          1) if $SUDO apt update && $SUDO apt install -y htop; then echo -e "\e[32mhtop 安装完成！\e[0m"; else echo -e "\e[31mhtop 安装失败！\e[0m"; fi ;;
          2) if $SUDO apt remove -y htop; then echo -e "\e[32mhtop 卸载完成！\e[0m"; else echo -e "\e[31mhtop 卸载失败！\e[0m"; fi ;;
        esac; pause ;;
      9)
        echo "1) 安装  2) 卸载"; read -p "请选择操作：" action
        case "$action" in
          1) if curl_exec "https://get.docker.com/" ; then echo -e "\e[32mdocker 安装完成！\e[0m"; else echo -e "\e[31mdocker 安装失败！\e[0m"; fi ;;
          2) if $SUDO apt remove -y docker; then echo -e "\e[32mdocker 卸载完成！\e[0m"; else echo -e "\e[31mdocker 卸载失败！\e[0m"; fi ;;
        esac; pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

# ------------------------- 申请证书 -------------------------
apply_certificate() {
  while true; do
    echo "========================================="
    echo -e "               \e[1;32m申请证书\e[0m"
    echo "========================================="
    echo "1) 安装脚本"
    echo "2) 申请证书"
    echo "3) 更换服务器"
    echo "4) 安装证书"
    echo "5) 卸载脚本"
    echo "========================================="
    read -p "请输入数字 [1-5] 选择 (默认回车退出)：" cert_choice
    case "$cert_choice" in
      1)
        read -p "请输入邮箱地址: " email
        $SUDO apt update
        command -v crontab >/dev/null 2>&1 || { echo "正在安装 cron..."; $SUDO apt install -y cron || echo -e "\e[31mcron 安装失败！\e[0m"; }
        command -v socat   >/dev/null 2>&1 || { echo "正在安装 socat..."; $SUDO apt install -y socat || echo -e "\e[31msocat 安装失败！\e[0m"; }
        if curl -fsSL https://get.acme.sh | sh -s email="$email"; then
          echo -e "\e[32macme.sh 安装完成！\e[0m"
        else
          echo -e "\e[31macme.sh 安装失败！\e[0m"
        fi
        pause ;;
      2)
        read -p "请输入域名: " domain
        if ~/.acme.sh/acme.sh --issue --standalone -d "$domain"; then
          echo -e "\e[32m证书申请成功！\e[0m"
        else
          echo -e "\e[31m证书申请失败，请检查域名。\e[0m"
        fi
        pause ;;
      3)
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt && \
          echo -e "\e[32m已切换至 Let's Encrypt！\e[0m" || echo -e "\e[31m切换失败。\e[0m"
        pause ;;
      4)
        read -p "请输入域名: " domain
        read -p "请输入证书安装路径（默认: /path/to）: " install_path
        install_path=${install_path:-/path/to}
        if mkdir -p "$install_path" && \
           ~/.acme.sh/acme.sh --installcert -d "$domain" \
             --key-file "$install_path/key.key" \
             --fullchain-file "$install_path/certificate.crt" && \
           $SUDO chmod 644 "$install_path/certificate.crt" "$install_path/key.key"; then
          echo -e "\e[32m证书安装完成！路径: $install_path\e[0m"
        else
          echo -e "\e[31m证书安装失败。\e[0m"
        fi
        pause ;;
      5)
        if ~/.acme.sh/acme.sh --uninstall; then echo -e "\e[32macme.sh 已卸载。\e[0m"; else echo -e "\e[31macme.sh 卸载失败！\e[0m"; fi
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

# ------------------------- 安装 Xray -------------------------
XRAY_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

install_xray() {
  while true; do
    echo "========================================="
    echo -e "               \e[1;32m安装Xray\e[0m"
    echo "========================================="
    echo "1) VMESS-WS-TLS"
    echo "2) VLESS-TCP-REALITY"
    echo "3) 卸载服务"
    echo "========================================="
    read -p "请输入数字 [1-3] 选择 (默认回车退出)：" opt_choice
    case "$opt_choice" in
      1) install_xray_tls ;;
      2) install_xray_reality ;;
      3)
        if curl_exec "$XRAY_URL" remove --purge; then
          echo -e "\e[32mXray 已卸载。\e[0m"
        else
          echo -e "\e[31mXray 卸载失败！\e[0m"
        fi
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

install_xray_tls() {
  while true; do
    echo "========================================="
    echo -e "               \e[1;34mVMESS-WS-TLS\e[0m"
    echo "========================================="
    echo "1) 安装升级"
    echo "2) 编辑配置"
    echo "3) 重启服务"
    echo "========================================="
    read -p "请输入数字 [1-3] 选择 (默认回车退出)：" xray_choice
    case "$xray_choice" in
      1)
        if curl_exec "$XRAY_URL" install && \
           $SUDO curl -fsSL -o /usr/local/etc/xray/config.json \
             "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VMess-Websocket-TLS/config_server.jsonc"; then
          echo -e "\e[32mXray 安装升级完成！\e[0m"
          echo "以下是 UUID："; echo -e "\e[34m$(xray uuid)\e[0m"
        else
          echo -e "\e[31mXray 安装升级失败！\e[0m"
        fi
        pause ;;
      2)
        echo -e "\e[33m提示：将 UUID 填入配置文件；若已用“申请证书”默认路径，无需改证书路径。\e[0m"
        pause
        need_editor || return 1
        $SUDO nano /usr/local/etc/xray/config.json
        pause ;;
      3)
        local CONFIG_PATH="/usr/local/etc/xray/config.json"
        extract_field() { grep -aPo "\"$1\":\s*$2" "$CONFIG_PATH" | head -n1 | sed -E "s/\"$1\":\s*//;s/^\"//;s/\"$//"; }
        extract_list_field() { grep -aPoz "\"$1\":\s*\[\s*\{[^}]*\}\s*\]" "$CONFIG_PATH" | grep -aPo "\"$2\":\s*\"[^\"]*\"" | head -n1 | sed -E "s/\"$2\":\s*\"([^\"]*)\"/\1/"; }

        $SUDO systemctl restart xray 2>/dev/null
        sleep 2
        if ! systemctl is-active --quiet xray; then
          echo -e "\e[31m未能启动 xray 服务，请检查日志。\e[0m"; systemctl status xray --no-pager; pause; return 1
        else
          echo -e "\e[32mxray已启动！\e[0m"
        fi

        local UUID PORT WS_PATH TLS CERT_PATH DOMAIN SNI HOST ADDRESS
        UUID=$(extract_list_field "clients" "id")
        PORT=$(extract_field "port" "\d+")
        WS_PATH=$(extract_field "path" "\"[^\"]*\"")
        TLS=$(extract_field "security" "\"[^\"]*\"")
        CERT_PATH=$(extract_list_field "certificates" "certificateFile")
        if [ -z "$CERT_PATH" ]; then echo -e "\e[31m未能找到证书路径。\e[0m"; pause; return 1; fi
        DOMAIN=$(get_domain_from_cert "$CERT_PATH")
        SNI=${DOMAIN:-"your.domain.net"}
        HOST=${DOMAIN:-"your.domain.net"}
        ADDRESS=$(get_public_ip)
        WS_PATH=${WS_PATH:-"/"}
        TLS=${TLS:-"tls"}
        PORT=${PORT:-"443"}

        local vmess_uri="vmess://${UUID}@${ADDRESS}:${PORT}?encryption=none&security=${TLS}&sni=${SNI}&type=ws&host=${HOST}&path=${WS_PATH}#Xray"
        echo "VMESS 链接如下："
        echo -e "\e[34m$vmess_uri\e[0m"
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

install_xray_reality() {
  while true; do
    echo "========================================="
    echo -e "            \e[1;34mVLESS-TCP-REALITY\e[0m"
    echo "========================================="
    echo "1) 安装升级"
    echo "2) 编辑配置"
    echo "3) 重启服务"
    echo "========================================="
    read -p "请输入数字 [1-3] 选择(默认回车退出)：" xray_choice
    case "$xray_choice" in
      1)
        if curl_exec "$XRAY_URL" install && \
           $SUDO curl -fsSL -o /usr/local/etc/xray/config.json \
             "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-TCP-REALITY%20(without%20being%20stolen)/config_server.jsonc"; then
          echo -e "\e[32mXray 安装升级完成！\e[0m"
          echo "以下是 UUID："; echo -e "\e[34m$(xray uuid)\e[0m"
          echo "以下是私钥："
          keys="$(xray x25519)"; export PRIVATE_KEY="$(echo "$keys" | awk 'NR==1{print $3}')" ; export PUBLIC_KEY="$(echo "$keys" | awk 'NR==2{print $3}')"
          echo -e "\e[34m$PRIVATE_KEY\e[0m"
          echo "以下是 ShortIds："; echo -e "\e[34m$(openssl rand -hex 8)\e[0m"
        else
          echo -e "\e[31mXray 安装升级失败！\e[0m"
        fi
        pause ;;
      2)
        echo -e "\e[33m提示：将 UUID、目标网站及私钥填入配置文件，ShortIds 可留空。\e[0m"
        pause
        need_editor || return 1
        $SUDO nano /usr/local/etc/xray/config.json
        pause ;;
      3)
        local CONFIG_PATH="/usr/local/etc/xray/config.json"
        remove_spaces_and_quotes(){ echo "$1" | sed 's/[[:space:]]*$//;s/^ *//;s/^"//;s/"$//'; }
        extract_field(){ grep -aPo "\"$1\":\s*$2" "$CONFIG_PATH" | head -n1 | sed -E "s/\"$1\":\s*//;s/^\"//;s/\"$//"; }
        extract_server_name(){ grep -A5 '"serverNames"' "$CONFIG_PATH" | grep -o '"[^"]*"' | sed -n '2{s/"//g;p}' ; }
        extract_list_field(){
          local list_field="$2"
          if [[ "$list_field" == "shortIds" || "$list_field" == "serverNames" ]]; then
            local result; result=$(grep -aA 2 "\"$list_field\": \[" "$CONFIG_PATH" | awk 'NR==2{gsub(/^\s+|\s*\/\/.*$/,"");split($0,a,","); for(i in a){gsub(/^["\s]+|["\s]+$/,"",a[i]);printf "%s ",a[i]}}')
            [ -n "$result" ] && remove_spaces_and_quotes "$result"
          else
            grep -aPoz "\"$1\":\s*\[\s*\{[^}]*\}\s*\]" "$CONFIG_PATH" | grep -aPo "\"$list_field\":\s*\"[^\"]*\"" | head -n1 | sed -E "s/\"$list_field\":\s*\"([^\"]*)\"/\1/"
          fi
        }

        $SUDO systemctl restart xray 2>/dev/null
        sleep 2
        if ! systemctl is-active --quiet xray; then
          echo -e "\e[31m未能启动 xray 服务，请检查日志。\e[0m"; systemctl status xray --no-pager; pause; return 1
        else
          echo -e "\e[32mxray已启动！\e[0m"
        fi

        local UUID PORT TLS SERVER_NAME SHORT_IDS SNI ADDRESS FLOW SID PBK
        UUID=$(extract_list_field "clients" "id")
        PORT=$(extract_field "port" "\d+")
        TLS=$(extract_field "security" "\"[^\"]*\"")
        SERVER_NAME=$(extract_server_name)
        SHORT_IDS=$(extract_list_field "realitySettings" "shortIds")
        SNI=${SERVER_NAME:-"your.domain.net"}
        ADDRESS=$(get_public_ip)
        PORT=${PORT:-"443"}
        FLOW=$(extract_field "flow" "\"[^\"]*\"")
        SID=${SHORT_IDS:-""}
        PBK=${PUBLIC_KEY}

        local vless_uri="vless://${UUID}@${ADDRESS}:${PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${SNI}&fp=chrome&pbk=${PBK}&sid=${SID}&type=tcp&headerType=none#Xray"
        echo "VLESS 链接如下："
        echo -e "\e[34m$vless_uri\e[0m"
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

# ------------------------- 安装 Hysteria2 -------------------------
install_hysteria2() {
  while true; do
    echo "========================================="
    echo -e "           \e[1;32m安装Hysteria2\e[0m"
    echo "========================================="
    echo "1) 安装升级"
    echo "2) 编辑配置"
    echo "3) 重启服务"
    echo "4) 端口跳跃"
    echo "5) 卸载服务"
    echo "========================================="
    read -p "请输入数字 [1-5] 选择 (默认回车退出)：" hysteria_choice
    case "$hysteria_choice" in
      1)
        if curl_exec "https://get.hy2.sh/"; then
          $SUDO systemctl enable --now hysteria-server.service
          $SUDO sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1 || true
          $SUDO sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1 || true
          echo -e "\e[32mhysteria2 安装升级完成！\e[0m"
        else
          echo -e "\e[31mhysteria2 安装升级失败！\e[0m"
        fi
        pause ;;
      2)
        echo -e "\e[33m提示：将域名填入配置文件中。\e[0m"
        pause
        need_editor || return 1
        $SUDO nano /etc/hysteria/config.yaml
        pause ;;
      3)
        local config_file="/etc/hysteria/config.yaml"
        [ -f "$config_file" ] || { echo -e "\e[31m未能找到配置文件。\e[0m"; pause; return 1; }
        $SUDO systemctl restart hysteria-server.service
        sleep 2
        if ! systemctl is-active --quiet hysteria-server.service; then
          echo -e "\e[31m未能启动 hysteria 服务，请检查日志。\e[0m"; $SUDO systemctl status hysteria-server.service --no-pager; pause; return 1
        else
          echo -e "\e[32mhysteria已启动！\e[0m"
        fi
        local port password domain cert_path ip
        port=$(awk -F: '/^listen:/{print $NF}' "$config_file")
        password=$(awk '/^  password:/{print $2}' "$config_file")
        domain=$(awk '/domains:/{getline; gsub(/^[ -]+/,""); print}' "$config_file")
        if [ -z "$domain" ]; then
          cert_path=$(awk -F\" '/cert:/{print $2}' "$config_file")
          [ -n "$cert_path" ] && domain="$(get_domain_from_cert "$cert_path")"
          [ -z "$domain" ] && echo -e "\e[31m从配置/证书中未获得域名。\e[0m"
        fi
        ip="$( get_public_ip )"
        [ -z "$port" ] && port=443
        local hysteria2_uri="hysteria2://$password@$ip:$port?sni=$domain&insecure=0#hysteria"
        echo "hysteria2 链接如下："
        echo -e "\e[34m$hysteria2_uri\e[0m"
        pause ;;
      4)
        local default_redirect_port=443 default_start_port=60000 default_end_port=65535
        local config_file="/etc/hysteria/config.yaml"
        local redirect_port
        if [[ -f "$config_file" ]]; then redirect_port=$(awk -F: '/listen:/{print $NF}' "$config_file"); fi
        [[ -z "$redirect_port" || ! "$redirect_port" =~ ^[0-9]+$ || "$redirect_port" -lt 1 || "$redirect_port" -gt 65535 ]] && redirect_port="$default_redirect_port"
        read -p "请输入起始端口号 (默认 60000): " start_port; start_port=${start_port:-$default_start_port}
        [[ ! "$start_port" =~ ^[0-9]+$ || "$start_port" -lt 1 || "$start_port" -gt 65535 ]] && { echo -e "\e[31m起始端口无效，使用默认 60000。\e[0m"; start_port=$default_start_port; }
        read -p "请输入结束端口号 (默认 65535): " end_port; end_port=${end_port:-$default_end_port}
        [[ ! "$end_port" =~ ^[0-9]+$ || "$end_port" -lt "$start_port" || "$end_port" -gt 65535 ]] && { echo -e "\e[31m结束端口无效，使用默认 65535。\e[0m"; end_port=$default_end_port; }
        local interfaces; mapfile -t interfaces < <(ip -o link | awk -F': ' '$2!="lo"{print $2}')
        [ "${#interfaces[@]}" -eq 0 ] && { echo -e "\e[31m未找到网络接口。\e[0m"; pause; return 1; }
        local selected_interface="${interfaces[0]}"
        if $SUDO iptables -t nat -A PREROUTING -i "$selected_interface" -p udp --dport "$start_port:$end_port" -j REDIRECT --to-ports "$redirect_port"; then
          echo -e "\e[32m端口跳跃设置成功！\e[0m"
        else
          echo -e "\e[31miptables 命令执行失败。\e[0m"
        fi
        pause ;;
      5)
        if curl_exec "https://get.hy2.sh/" --remove && \
           rm -rf /etc/hysteria && userdel -r hysteria 2>/dev/null && \
           rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service \
                 /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service && \
           systemctl daemon-reload; then
          echo -e "\e[32mhysteria2 已卸载。\e[0m"
        fi
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

# ------------------------- 安装 sing-box -------------------------
install_sing-box() {
  while true; do
    echo "========================================="
    echo -e "           \e[1;32m安装sing-box\e[0m"
    echo "========================================="
    echo "1) 安装升级"
    echo "2) 编辑配置"
    echo "3) 重启服务"
    echo "4) 卸载服务"
    echo "========================================="
    read -p "请输入数字 [1-4] 选择 (默认回车退出)：" singbox_choice
    case "$singbox_choice" in
      1)
        if curl_exec "https://sing-box.app/deb-install.sh" && \
           $SUDO curl -fsSL -o /etc/sing-box/config.json \
             "https://raw.githubusercontent.com/sezhai/VPS-Script/refs/heads/main/extras/sing-box/config.json"; then
          echo -e "\e[32msing-box 安装升级成功！\e[0m"
          echo "以下是 UUID："; echo -e "\e[34m$(sing-box generate uuid)\e[0m"
          keys="$(sing-box generate reality-keypair)"; export PRIVATE_KEY="$(echo "$keys" | awk '/PrivateKey/{print $2}')" ; export PUBLIC_KEY="$(echo "$keys" | awk '/PublicKey/{print $2}')"
          echo "以下是私钥："; echo -e "\e[34m$PRIVATE_KEY\e[0m"
          echo "以下是 ShortIds："; echo -e "\e[34m$(sing-box generate rand 8 --hex)\e[0m"
        else
          echo -e "\e[31msing-box 安装升级失败！\e[0m"
        fi
        pause ;;
      2)
        echo -e "\e[33m提示：根据提示修改配置文件。\e[0m"
        pause
        need_editor || return 1
        $SUDO nano /etc/sing-box/config.json
        pause ;;
      3)
        local CONFIG_PATH="/etc/sing-box/config.json"
        $SUDO systemctl restart sing-box
        sleep 2
        if ! systemctl is-active --quiet sing-box; then
          echo -e "\e[31m未能启动 sing-box 服务，请检查日志。\e[0m"; systemctl status sing-box --no-pager; pause; return 1
        else
          echo -e "\e[32msing-box已启动！\e[0m"
        fi
        get_ip(){
          local ip
          ip="$(curl -fsS -4 https://api.ipify.org 2>/dev/null || true)"; [ -n "$ip" ] && { echo "$ip"; return; }
          ip="$(curl -fsS -6 https://api64.ipify.org 2>/dev/null || true)"; [ -n "$ip" ] && { echo "$ip"; return; }
          echo "127.0.0.1"
        }
        urlencode(){ local s="$1" ch; for((i=0;i<${#s};i++)); do ch="${s:i:1}"; case "$ch" in [a-zA-Z0-9.~_-]) printf '%s' "$ch" ;; *) printf '%%%02X' "'$ch" ;; esac; done; }
        get_domain_from_cert_l(){ get_domain_from_cert "$1"; }

        local ip ip_for_url; ip="$(get_ip)"; [[ "$ip" =~ : ]] && ip_for_url="[$ip]" || ip_for_url="$ip"

        # vmess
        if grep -q '"tag":\s*"vmess"' "$CONFIG_PATH"; then
          local vmess_uuid vmess_port vmess_path vmess_host
          vmess_uuid=$(grep -A20 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"uuid":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
          vmess_port=$(grep -A5  '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')
          vmess_path=$(grep -A30 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"path":\s*"[^"]*"' | cut -d'"' -f4)
          vmess_host=$(grep -A30 '"tag":\s*"vmess"' "$CONFIG_PATH" | grep -o '"server_name":\s*"[^"]*"' | cut -d'"' -f4)
          if [ -n "$vmess_uuid" ] && [ -n "$vmess_port" ]; then
            local vmess_json; vmess_json='{"v":"2","ps":"vmess","add":"'$ip'","port":"'$vmess_port'","id":"'$vmess_uuid'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'$vmess_host'","path":"'$vmess_path'","tls":"tls","sni":"'$vmess_host'","alpn":"http/1.1","fp":"chrome"}'
            echo "vmess 链接如下："; echo -e "\e[34mvmess://$(echo -n "$vmess_json" | base64 -w0)\e[0m"
          fi
        fi
        # reality
        if grep -q '"tag":\s*"reality"' "$CONFIG_PATH"; then
          local vless_uuid vless_port vless_sni vless_sid
          vless_uuid=$(grep -A20 '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"uuid":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
          vless_port=$(grep -A5  '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')
          vless_sni=$(grep -A30 '"tag":\s*"reality"' "$CONFIG_PATH" | grep -o '"server_name":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
          vless_sid=$(grep -A30 '"tag":\s*"reality"' "$CONFIG_PATH" | sed -n '/"short_id"/,/]/p' | grep -o '"[a-fA-F0-9]*"' | head -1 | tr -d '"')
          if [ -n "$vless_uuid" ] && [ -n "$vless_port" ]; then
            local vless_link="vless://$vless_uuid@$ip_for_url:$vless_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vless_sni&fp=chrome&pbk=$PUBLIC_KEY&sid=$vless_sid&type=tcp&headerType=none#reality"
            echo "reality 链接如下："; echo -e "\e[34m$vless_link\e[0m"
          fi
        fi
        # hysteria2
        if grep -q '"tag":\s*"hysteria2"' "$CONFIG_PATH"; then
          local h2_pass h2_port cert_path h2_domain
          h2_pass=$(grep -A20 '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"password":\s*"[^"]*"' | cut -d'"' -f4)
          h2_port=$(grep -A5  '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"listen_port":\s*[0-9]*' | cut -d':' -f2 | tr -d ' ,')
          cert_path=$(grep -A30 '"tag":\s*"hysteria2"' "$CONFIG_PATH" | grep -o '"certificate_path":\s*"[^"]*"' | cut -d'"' -f4)
          [ -n "$cert_path" ] && [ -f "$cert_path" ] && h2_domain="$(get_domain_from_cert_l "$cert_path")"
          if [ -n "$h2_pass" ] && [ -n "$h2_port" ] && [ -n "$h2_domain" ]; then
            echo "hysteria2 链接如下："; echo -e "\e[34mhysteria2://$(urlencode "$h2_pass")@$ip_for_url:$h2_port?sni=$h2_domain&insecure=0#hysteria2\e[0m"
          fi
        fi
        pause ;;
      4)
        if systemctl disable --now sing-box && rm -f /usr/local/bin/sing-box /etc/systemd/system/sing-box.service && rm -rf /var/lib/sing-box /etc/sing-box; then
          echo -e "\e[32msing-box 已卸载。\e[0m"
        fi
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

# ------------------------- 安装 1Panel -------------------------
install_1panel() {
  while true; do
    echo "========================================="
    echo -e "               \e[1;32m安装1Panel\e[0m"
    echo "========================================="
    echo "1) 安装面板"
    echo "2) 查看信息"
    echo "3) 安装防火墙"
    echo "4) 卸载防火墙"
    echo "5) 卸载面板"
    echo "========================================="
    read -p "请输入数字 [1-5] 选择 (默认回车退出)：" panel_choice
    case "$panel_choice" in
      1)
        if curl -fsSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && $SUDO bash quick_start.sh; then
          echo -e "\e[32m1Panel 安装完成！\e[0m"
        else
          echo -e "\e[31m1Panel 安装失败！\e[0m"
        fi
        pause ;;
      2) 1pctl user-info; pause ;;
      3) if $SUDO apt install -y ufw; then echo -e "\e[32mufw 安装完成！\e[0m"; else echo -e "\e[31mufw 安装失败！\e[0m"; fi; pause ;;
      4) if $SUDO apt remove -y ufw && $SUDO apt purge -y ufw && $SUDO apt autoremove -y; then echo -e "\e[32mufw 卸载完成。\e[0m"; else echo -e "\e[31mufw 卸载失败！\e[0m"; fi; pause ;;
      5)
        if $SUDO systemctl stop 1panel && $SUDO 1pctl uninstall && $SUDO rm -rf /var/lib/1panel /etc/1panel /usr/local/bin/1pctl && $SUDO journalctl --vacuum-time=3d && \
           $SUDO systemctl stop docker && $SUDO apt-get purge -y docker-ce docker-ce-cli containerd.io && \
           $SUDO find / \( -name "1panel*" -o -name "docker*" -o -name "containerd*" -o -name "compose*" \) -exec rm -rf {} + && \
           $SUDO groupdel docker 2>/dev/null; then
          echo -e "\e[32m1Panel 卸载完成。\e[0m"
        fi
        pause ;;
      "") return ;;
      *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
    esac
  done
}

# ------------------------- 主循环 -------------------------
while true; do
  display_main_menu
  read -p "请输入数字 [1-9] 选择(默认回车退出)：" choice
  if [ -z "$choice" ]; then echo -e "\e[32m退出脚本，感谢使用！\e[0m"; exit 0; fi
  case "$choice" in
    1) view_vps_info ;;
    2) display_system_optimization_menu ;;
    3) common_tools ;;
    4) install_package ;;
    5) apply_certificate ;;
    6) install_xray ;;
    7) install_hysteria2 ;;
    8) install_sing-box ;;
    9) install_1panel ;;
    *) echo -e "\e[31m无效选项，请输入 1-9 或回车退出！\e[0m" ;;
  esac
done
