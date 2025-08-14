#!/usr/bin/env bash
# 一键安全清理后装服务/应用 -- Debian/Ubuntu
# 默认执行模式：--apply --purge-all
set -euo pipefail

# --- 自动给自己赋权 ---
if [[ ! -x "$0" ]]; then
    echo "[INFO] 检测到脚本无执行权限，正在赋予执行权限..."
    chmod +x "$0"
    echo "[INFO] 重新执行脚本..."
    exec "$0" "$@"
fi

APPLY=true
PURGE_ALL=true

log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
run() { bash -c "$*"; }

# --- 保护服务与包 ---
PROTECTED_SERVICES=( "ssh" "sshd" "systemd-resolved" "systemd-networkd" "NetworkManager" )
PROTECTED_PACKAGES=(
  "openssh-server" "openssh-client" "sudo" "apt" "apt-utils" "ubuntu-minimal"
  "ubuntu-server" "base-files" "base-passwd" "bash" "coreutils" "systemd"
  "systemd-sysv" "init" "login" "passwd" "tzdata" "netplan.io" "ifupdown"
  "cloud-init"
)

# --- 目标清理服务与包 ---
TARGET_SERVICES=(
  "nginx" "apache2" "caddy" "haproxy" "traefik"
  "cloudflared" "argo"
  "docker" "docker.socket" "docker.service" "containerd" "podman"
  "frps" "xray" "v2ray" "sing-box" "hysteria" "hysteria-server"
  "trojan" "trojan-go" "shadowsocks" "ssserver" "sslocal"
)
TARGET_PACKAGES=(
  "nginx" "nginx-full" "nginx-core" "apache2" "caddy" "haproxy" "traefik"
  "cloudflared"
  "docker.io" "docker-ce" "docker-ce-cli" "containerd" "containerd.io" "podman"
  "xray" "v2ray" "sing-box" "hysteria"
  "trojan" "trojan-go" "shadowsocks" "shadowsocks-libev"
  "nodejs" "npm"
)
TARGET_BINARIES=(
  "cloudflared" "argo" "nginx" "caddy" "haproxy" "traefik"
  "docker" "containerd" "runc" "ctr" "nerdctl" "podman"
  "frps" "xray" "v2ray" "sing-box" "hysteria" "hysteria-server"
  "trojan" "trojan-go" "ssserver" "sslocal"
)
TARGET_DIRS=(
  "/etc/cloudflared" "/etc/argo" "/etc/nginx" "/etc/apache2" "/etc/caddy"
  "/etc/haproxy" "/etc/traefik"
  "/etc/xray" "/etc/v2ray" "/etc/sing-box" "/etc/hysteria" "/etc/trojan" "/etc/shadowsocks"
  "/var/www" "/var/log/nginx" "/var/log/apache2" "/var/lib/docker" "/var/run/docker"
  "/opt/*"
)
EXCLUDE_PACKAGES=()

is_installed_pkg() { dpkg -s "$1" &>/dev/null; }
has_cmd() { command -v "$1" &>/dev/null; }

log "======== 一键清理后装应用（执行模式）========"

# 停止并禁用服务
log "停止并禁用目标服务"
for svc in "${TARGET_SERVICES[@]}"; do
  if systemctl list-unit-files | grep -qE "^${svc}\.service"; then
    if [[ " ${PROTECTED_SERVICES[*]} " == *" $svc "* ]]; then
      warn "跳过受保护服务: $svc"
      continue
    fi
    systemctl stop "$svc" || true
    systemctl disable "$svc" || true
    systemctl mask "$svc" || true
  fi
done
systemctl daemon-reload

# 杀掉监听进程
log "结束相关监听进程"
LISTEN_PIDS=$(ss -plntuH 2>/dev/null | awk -F',' '{print $2}' | awk '{print $1}' | sed 's/pid=//' | sort -u || true)
for pid in $LISTEN_PIDS; do
  comm=$(basename "$(readlink -f /proc/$pid/exe 2>/dev/null || echo '')" || true)
  name=$(cat /proc/$pid/comm 2>/dev/null || echo "")
  for k in "${TARGET_BINARIES[@]}"; do
    if [[ "$comm" == "$k" || "$name" == "$k" ]]; then
      warn "杀掉进程 pid=$pid ($name)"
      kill -TERM "$pid" || true
      sleep 0.5
      kill -KILL "$pid" || true
    fi
  done
done

# 卸载软件包
log "卸载目标软件包"
TO_REMOVE=()
for pkg in "${TARGET_PACKAGES[@]}"; do
  if [[ " ${EXCLUDE_PACKAGES[*]} " == *" $pkg "* ]]; then
    warn "排除包：$pkg"
    continue
  fi
  if [[ " ${PROTECTED_PACKAGES[*]} " == *" $pkg "* ]]; then
    warn "受保护包：$pkg"
    continue
  fi
  if is_installed_pkg "$pkg"; then
    TO_REMOVE+=("$pkg")
  fi
done
if (( ${#TO_REMOVE[@]} > 0 )); then
  apt-get remove --purge -y "${TO_REMOVE[@]}"
  apt-get autoremove --purge -y
  apt-get clean
else
  log "没有发现已安装的目标包"
fi

# 删除手动安装的二进制
log "删除手动安装的二进制文件"
for b in "${TARGET_BINARIES[@]}"; do
  for path in "/usr/local/bin/$b" "/usr/local/sbin/$b" "/usr/bin/$b" "/usr/sbin/$b"; do
    [[ -f "$path" ]] && rm -f "$path"
  done
done

# 清理自启动项
log "清理 crontab 与 rc.local 中的相关启动项"
for who in "" "sudo"; do
  if $who crontab -l >/dev/null 2>&1; then
    TMP=$(mktemp)
    $who crontab -l > "$TMP" || true
    for k in "${TARGET_BINARIES[@]}"; do
      sed -i "/$k/d" "$TMP"
    done
    $who crontab "$TMP"
    rm -f "$TMP"
  fi
done
if [[ -f /etc/rc.local ]]; then
  TMP=$(mktemp)
  cp /etc/rc.local "$TMP"
  for k in "${TARGET_BINARIES[@]}"; do
    sed -i "/$k/d" "$TMP"
  done
  install -m 755 "$TMP" /etc/rc.local
  rm -f "$TMP"
fi

# 删除配置与数据目录
log "删除配置/日志/数据目录"
for d in "${TARGET_DIRS[@]}"; do
  rm -rf $d
done

# 清理 snap
if has_cmd snap; then
  log "移除 snap 中的相关包"
  SNAP_CANDIDATES=( "docker" "caddy" "nginx" "node" )
  for s in "${SNAP_CANDIDATES[@]}"; do
    if snap list | awk '{print $1}' | grep -qx "$s"; then
      snap remove --purge "$s" || true
    fi
  done
fi

# 最终检查
log "清理完成，当前监听端口："
ss -plntu || true
