#!/bin/bash
# VPS 管理脚本

# -----------------------------------------------------------------------------
# 函数定义
# -----------------------------------------------------------------------------

# 主菜单函数
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

# 系统信息
view_vps_info() {
    echo -e "\e[1;34m主机名:\e[0m \e[32m$(hostname)\e[0m"
    echo -e "\e[1;34m系统版本:\e[0m \e[32m$(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d '"' -f2)\e[0m"
    echo -e "\e[1;34mLinux版本:\e[0m \e[32m$(uname -r)\e[0m"
    echo "-------------"
    echo -e "\e[1;34mCPU架构:\e[0m \e[32m$(uname -m)\e[0m"
    echo -e "\e[1;34mCPU型号:\e[0m \e[32m$(lscpu | grep 'Model name' | sed 's/Model name:[ \t]*//')\e[0m"
    echo -e "\e[1;34mCPU核心数:\e[0m \e[32m$(nproc)\e[0m"
    echo -e "\e[1;34mCPU频率:\e[0m \e[32m$(lscpu | grep 'CPU MHz' | awk -F: '{print $2}' | xargs) MHz\e[0m"
    echo "-------------"
    echo -e "\e[1;34mCPU占用:\e[0m \e[32m$(top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}')%\e[0m"
    echo -e "\e[1;34m系统负载:\e[0m \e[32m$(awk '{print $1, $2, $3}' /proc/loadavg)\e[0m"
    local mem_info=$(free -m | awk '/Mem:/ {total=$2; used=$3; if (total > 0) printf "%.2f/%.2f MB (%.2f%%)", used, total, used*100/total; else print "数据不可用"}')
    echo -e "\e[1;34m物理内存:\e[0m \e[32m$mem_info \e[0m"
    local swap_info=$(free -m | awk '/Swap:/ {total=$2; used=$3; if (total > 0) printf "%.0fMB/%.0fMB (%.0f%%)", used, total, used*100/total; else print "数据不可用" }')
    echo -e "\e[1;34m虚拟内存:\e[0m \e[32m$swap_info\e[0m"
     
    echo -e "\e[1;34m硬盘占用:\e[0m \e[32m$(df -h / | awk '/\// {print $3 "/" $2 " (" $5 ")"}')\e[0m"
    echo "-------------"
    local NET_INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}' | head -n 1)
    if [ -n "$NET_INTERFACE" ]; then
        local RX_BYTES=$(cat /sys/class/net/$NET_INTERFACE/statistics/rx_bytes)
        local TX_BYTES=$(cat /sys/class/net/$NET_INTERFACE/statistics/tx_bytes)
        local RX_MB=$(awk "BEGIN {printf \"%.2f\", $RX_BYTES / 1024 / 1024}")
        local TX_MB=$(awk "BEGIN {printf \"%.2f\", $TX_BYTES / 1024 / 1024}")
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
    echo -e "\e[1;34m运营商:\e[0m \e[32m$(curl -s ipinfo.io/org | sed 's/^ *//;s/ *$//')\e[0m"
    echo -e "\e[1;34mIPv4地址:\e[0m \e[32m$(curl -s ipv4.icanhazip.com)\e[0m"
    echo -e "\e[1;34mIPv6地址:\e[0m \e[32m$(ip -6 addr show scope global | awk '/inet6/ && !/temporary|tentative/ {print $2}' | cut -d'/' -f1 | head -n1 | ( grep . || echo "未检测到IPv6地址" ))\e[0m"
    echo -e "\e[1;34mDNS地址:\e[0m \e[32m$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | xargs | sed 's/ /, /g')\e[0m"
    echo -e "\e[1;34m地理位置:\e[0m \e[32m$(curl -s ipinfo.io/city), $(curl -s ipinfo.io/country)\e[0m"
    echo -e "\e[1;34m系统时间:\e[0m \e[32m$(timedatectl | grep 'Local time' | awk '{print $3, $4, $5}')\e[0m"
    echo "-------------"
    echo -e "\e[1;34m运行时长:\e[0m \e[32m$(uptime -p | sed 's/up //')\e[0m"
    echo "-------------"
    read -n 1 -s -r -p "按任意键返回..."
}

# 系统优化
display_system_optimization_menu() {
    while true; do
        echo "========================================="
    echo -e "               \e[1;32m系统优化\e[0m       "
        echo "========================================="
        echo "1) 校准时间"
        echo "2) 更新系统"
        echo "3) 清理系统"
        echo "4) 开启BBR"
        echo "5) ROOT登录"
        echo "========================================="
        read -p "请输入数字 [1-5] 选择 (默认回车退出)：" root_choice
        case "$root_choice" in
            1) calibrate_time ;;
            2) update_system ;;
            3) clean_system ;;
            4) enable_bbr ;;
            5) root_login ;;
            "") 
                return
                ;;            
            *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
        esac
    done
}

# 时间校准
calibrate_time() {
    echo -e "\n[校准时间]"
    sudo timedatectl set-timezone Asia/Shanghai
    sudo timedatectl set-ntp true
    echo -e "\e[32m时间校准完成，当前时区为 Asia/Shanghai。\e[0m"
    read -n 1 -s -r -p "按任意键返回..."
    echo
}

# 系统更新
update_system() {
    echo -e "\n[更新系统]"
    if ! sudo apt update -y && ! sudo apt full-upgrade -y; then
        echo -e "\e[31m系统更新失败！请检查网络连接或源列表。\e[0m"
    else
      sudo apt autoremove -y && sudo apt autoclean -y
        echo -e "\e[32m系统更新完成！\e[0m"
    fi
    read -n 1 -s -r -p "按任意键返回..."
    echo
}

# 系统清理
clean_system() {
    echo -e "\n[清理系统]"
    sudo apt autoremove --purge -y
    sudo apt clean -y && sudo apt autoclean -y
    sudo journalctl --rotate && sudo journalctl --vacuum-time=10m
    sudo journalctl --vacuum-size=50M
    echo -e "\e[32m系统清理完成！\e[0m"
    read -n 1 -s -r -p "按任意键返回..."
    echo
}

# 开启 BBR
enable_bbr() {
    echo -e "\n[开启BBR]"
    if sysctl net.ipv4.tcp_congestion_control | grep -q 'bbr'; then
    echo -e "\e[32mBBR已开启！\e[0m"
    else
        echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control = bbr" | sudo tee -a /etc/sysctl.conf
        if sudo sysctl -p; then
           echo -e "\e[32mBBR已开启！\e[0m"
        else
            echo -e "\e[31mBBR 开启失败！\e[0m"
        fi
    fi
    read -n 1 -s -r -p "按任意键返回..."
    echo
}

# ROOT登录
root_login() {
    while true; do
        echo "========================================="
        echo -e "               \e[1;34mROOT登录\e[0m   "
        echo "========================================="
        echo "1) 设置密码"
        echo "2) 修改配置"
        echo "3) 重启服务"
        echo "========================================="
        read -p "请输入数字 [1-3] 选择 (默认回车退出)：" root_choice
        case "$root_choice" in
            1) 
                sudo passwd root
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            2) 
                sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config;
                sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config;
                echo -e "\e[32m配置修改成功！\e[0m"
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            3)
                if sudo systemctl restart sshd.service; then
                   echo -e "\e[32mROOT登录已开启！\e[0m"
                else
                    echo -e "\e[31mROOT登录开启失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;            
            *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
        esac
    done
}

# 常用工具
common_tools() {
    while true; do
        echo "========================================="
        echo -e "               \e[1;32m常用工具\e[0m "
        echo "========================================="
        echo "1) 查找文件"
        echo "2) 赋予权限"        
        echo "3) 删除文件"
        echo "4) 查看进程"
        echo "5) 关闭进程"
        echo "6) 查看端口"
        echo "7) 开放端口"
        echo "========================================="
        read -p "请输入数字 [1-7] 选择 (默认回车退出)：" root_choice
        case "$root_choice" in
            1)
                read -p "请输入要查找的文件名: " filename
                if [[ -z "$filename" ]]; then
                    echo -e "\e[31m文件名不能为空。\e[0m"
                else
                    find / -type f -name "*$filename*" 2>/dev/null
                    [[ $? -ne 0 ]] && echo -e "\e[31m未找到匹配的文件。\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            2)
                read -p "请输入文件路径: " file_path
                if [ ! -e "$file_path" ]; then
                echo -e "\e[31m错误: 文件或目录 '$file_path' 不存在。\e[0m"
                exit 1
                fi
                chmod 755 "$file_path"
                if [ $? -eq 0 ]; then
                echo -e "\e[32m'$file_path' 权限已设置为 755！\e[0m"
                else
                    echo -e "\e[31m错误: 设置 '$file_path' 权限为 755 失败。\e[0m"
                exit 1
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            
            3)
                while true; do
                    read -p "请输入要删除的文件或目录名（默认回车退出）: " filename
                    if [[ -z "$filename" ]]; then
                        break
                    fi
                    files=($(find / -type f -iname "*$filename*" -o -type d -iname "*$filename*" 2>/dev/null))
                    if [[ ${#files[@]} -eq 0 ]]; then
                        echo -e "\e[31m未找到匹配的文件或目录。\e[0m"
                        continue
                    fi
                    echo "找到以下文件或目录:"
                    for i in "${!files[@]}"; do
                        echo "$((i+1)). ${files[$i]}"
                    done
                read -p "请输入要删除的文件或目录编号（可多选，使用空格分隔，按回车取消删除): " choices
                if [[ -z "$choices" ]]; then
                    echo "取消删除操作。"
                    continue
                    fi
                    IFS=' ' read -r -a choice_array <<< "$choices"
                    for choice in "${choice_array[@]}"; do
                        if [[ "$choice" -ge 1 && "$choice" -le ${#files[@]} ]]; then
                            file="${files[$((choice-1))]}"
                            read -p "确定要删除 $file 吗？ (y/n): " confirm
                            if [[ "$confirm" == "y" ]]; then
                                if [[ -d "$file" ]]; then
                                    rm -rf "$file"
                                    echo -e "\e[32m目录已删除: $file\e[0m"
                                else
                                    rm -f "$file"
                                    echo -e "\e[32m文件已删除: $file\e[0m"
                                fi
                            else
                                echo "取消删除 $file。"
                            fi
                        else
                            echo -e "\e[31m无效的选择: $choice\e[0m"
                        fi
                    done
                done
                echo
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;
            4)
                ps aux
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            5)
                while true; do
                    read -p "请输入要关闭的进程 PID: " pid
                    if [[ "$pid" =~ ^[0-9]+$ ]]; then
                        if kill "$pid"; then
                            echo -e "\e[32m进程 $pid 已成功关闭！\e[0m"
                        else
                            echo -e "\e[31m进程 $pid 无法正常关闭 (SIGTERM)，是否需要强制关闭 (SIGKILL)？ (y/n)\e[0m"
                            read -p "请选择 (y/n): " choice
                            if [[ "$choice" == "y" ]]; then
                                if kill -9 "$pid"; then
                                    echo -e "\e[32m进程 $pid 已被强制关闭！\e[0m"
                                else
                                    echo -e "\e[31m进程 $pid 强制关闭失败。\e[0m"
                                fi
                            elif [[ "$choice" == "n" ]]; then
                                echo "取消强制关闭"
                            else
                                echo -e "\e[31m无效的选项，进程未关闭。\e[0m"
                            fi
                        fi
                        break
                    else
                        echo -e "\e[31m无效的 PID，请输入一个整数。\e[0m"
                    fi
                done
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            6)
                if command -v ss &>/dev/null; then
                    echo -e "端口     类型    程序名               PID"
                    ss -tulnp | awk 'NR>1 {
                        split($5, a, ":");
                        split($7, b, ",");
                        gsub(/[()]/, "", b[1]);
                        gsub(/pid=/, "", b[2]);
                        gsub(/users:/, "", b[1]);
                        gsub(/"/, "", b[1]);
                        if (a[2] != "" && a[2] != "*") {
                            printf "%-8s %-7s %-20s %-6s\n", a[2], $1, b[1], b[2];
                        }
                    }'
                else
                    echo -e "端口     类型    程序名               PID"
                    netstat -tulnp | awk 'NR>2 {
                        split($4, a, ":");
                        split($7, b, "/");
                        gsub(/[()]/, "", b[1]);
                        gsub(/pid=/, "", b[2]);
                        gsub(/users:/, "", b[1]);
                        gsub(/"/, "", b[1]);
                        if (a[2] != "" && a[2] != "*") {
                            printf "%-8s %-7s %-20s %-6s\n", a[2], $1, b[1], b[2];
                        }
                    }'
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            7)
                while true; do
                    echo "请选择协议:"
                    echo "1) TCP"
                    echo "2) UDP"
                    read -p "请输入1或2: " protocol_choice
                    case "$protocol_choice" in
                        1) protocol="tcp" ;;
                        2) protocol="udp" ;;
                        *) echo -e "\e[31m无效的选择，请输入1或2。\e[0m"
                    break
                    esac
                    read -p "请输入端口号: " port
                    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                        echo -e "\e[31m无效的端口号，请输入1到65535之间的数字。\e[0m"
                    break
                    fi
                    command="sudo iptables -A INPUT -p $protocol --dport $port -j ACCEPT"
                    if $command; then
                        echo -e "\e[32m端口$port已开放（$protocol）!\e[0m"
                    else
                        echo -e "\e[31m执行命令失败。\e[0m"
                    fi
                    break
                done
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;            
            *)
                echo -e "\e[31m无效选项，请重新输入。\e[0m"
                ;;
        esac
    done
}

# 常用软件包
install_package() {
    while true; do
        echo "========================================="
        echo -e "               \e[1;32m常用软件包\e[0m   "
        echo "========================================="
        echo "1) apt"
        echo "2) sudo"
        echo "3) curl"
        echo "4) nano"
        echo "5) vim"
        echo "6) zip"
        echo "7) git"
        echo "8) htop"        
        echo "9) docker"
        echo "========================================="
        read -p "请输入数字 [1-7] 选择 (默认回车退出)：" opt_choice
        case "$opt_choice" in
            1)  
                if apt update; then
                    echo -e "\e[32mapt 更新完成！\e[0m"
                else
                    echo -e "\e[31mapt 更新失败！请检查网络连接或源列表。\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            2)
                echo "1) 安装"
                echo "2) 卸载"
                read -p "请选择操作 (默认回车退出)：" action
                case "$action" in
                    1) if apt update && apt install sudo -y; then
                            echo -e "\e[32msudo 安装完成！\e[0m"
                        else
                            echo -e "\e[31msudo 安装失败！\e[0m"
                        fi
                         ;;
                    2) if sudo apt update && sudo apt remove -y sudo; then
                            echo -e "\e[32msudo 卸载完成！\e[0m"
                        else
                             echo -e "\e[31msudo 卸载失败！\e[0m"
                        fi
                        ;;
                    "") ;;
                    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
                esac
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;                        
            3)
                echo "1) 安装"
                echo "2) 卸载"
                read -p "请选择操作 (默认回车退出)：" action
                case "$action" in
                    1) if sudo apt update && sudo apt install -y curl; then
                           echo -e "\e[32mcurl 安装完成！\e[0m"
                        else
                            echo -e "\e[31mcurl 安装失败！\e[0m"
                        fi
                        ;;
                    2) if sudo apt remove -y curl; then
                            echo -e "\e[32mcurl 卸载完成！\e[0m"
                        else
                            echo -e "\e[31mcurl 卸载失败！\e[0m"
                        fi
                        ;;
                    "") ;;
                    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
                esac
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;
            4)
                echo "1) 安装"
                echo "2) 卸载"
                read -p "请选择操作 (默认回车退出)：" action
                case "$action" in
                    1) if sudo apt update && sudo apt install -y nano; then
                            echo -e "\e[32mnano 安装完成！\e[0m"
                        else
                            echo -e "\e[31mnano 安装失败！\e[0m"
                        fi
                         ;;
                    2) if sudo apt remove -y nano; then
                            echo -e "\e[32mnano 卸载完成！\e[0m"
                        else
                             echo -e "\e[31mnano 卸载失败！\e[0m"
                        fi
                        ;;
                    "") ;;
                    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
                esac
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;
            5)
                echo "1) 安装"
                echo "2) 卸载"
                read -p "请选择操作 (默认回车退出)：" action
                case "$action" in
                    1) if sudo apt update && sudo apt install -y vim; then
                            echo -e "\e[32mvim 安装完成！\e[0m"
                        else
                            echo -e "\e[31mvim 安装失败！\e[0m"
                        fi
                         ;;
                    2) if sudo apt remove -y vim; then
                            echo -e "\e[32mvim 卸载完成！\e[0m"
                        else
                             echo -e "\e[31mvim 卸载失败！\e[0m"
                        fi
                        ;;
                    "") ;;
                    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
                esac
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;
            6)
                echo "1) 安装"
                echo "2) 卸载"
                read -p "请选择操作 (默认回车退出)：" action
                case "$action" in
                    1) if sudo apt update && sudo apt install -y zip; then
                            echo -e "\e[32mzip 安装完成！\e[0m"
                        else
                            echo -e "\e[31mzip 安装失败！\e[0m"
                        fi
                         ;;
                    2) if sudo apt remove -y zip; then
                            echo -e "\e[32mzip 卸载完成！\e[0m"
                        else
                             echo -e "\e[31mzip 卸载失败！\e[0m"
                        fi
                        ;;
                    "") ;;
                    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
                esac
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;                
            7)
                echo "1) 安装"
                echo "2) 卸载"
                read -p "请选择操作 (默认回车退出)：" action
                case "$action" in
                    1) if sudo apt update && sudo apt install -y git; then
                            echo -e "\e[32mgit 安装完成！\e[0m"
                        else
                           echo -e "\e[31mgit 安装失败！\e[0m"
                        fi
                         ;;
                    2)  if sudo apt remove -y git; then
                            echo -e "\e[32mgit 卸载完成！\e[0m"
                         else
                            echo -e "\e[31mgit 卸载失败！\e[0m"
                         fi
                        ;;
                    "") ;;
                    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
                esac
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;            
            8)
                echo "1) 安装"
                echo "2) 卸载"
                read -p "请选择操作 (默认回车退出)：" action
                case "$action" in
                    1) if sudo apt update && sudo apt install -y htop; then
                            echo -e "\e[32mhtop 安装完成！\e[0m"
                        else
                            echo -e "\e[31mhtop 安装失败！\e[0m"
                        fi
                         ;;
                    2) if sudo apt remove -y htop; then
                           echo -e "\e[32mhtop 卸载完成！\e[0m"
                        else
                            echo -e "\e[31mhtop 卸载失败！\e[0m"
                         fi
                        ;;
                    "") ;;
                    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
                esac
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;
            9)
                echo "1) 安装"
                echo "2) 卸载"
                read -p "请选择操作 (默认回车退出)：" action
                case "$action" in
                    1) if curl -sSL https://get.docker.com/ | sh; then
                            echo -e "\e[32mdocker 安装完成！\e[0m"
                        else
                            echo -e "\e[31mdocker 安装失败！\e[0m"
                        fi
                         ;;
                    2) if sudo apt remove -y docker; then
                            echo -e "\e[32mdocker 卸载完成！\e[0m"
                         else
                            echo -e "\e[31mdocker 卸载失败！\e[0m"
                        fi
                         ;;
                    "") ;;
                    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
                esac
                read -n 1 -s -r -p "按任意键返回..."
                echo                
                ;;
            "") 
                return
                ;;            
            *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
        esac
    done
}

# 申请证书
apply_certificate() {
    while true; do
        echo "========================================="
        echo -e "               \e[1;32m申请证书\e[0m     "
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
                sudo apt update
                if ! command -v crontab &> /dev/null; then
                    echo "正在安装 cron..."
                    if sudo apt install -y cron; then
                        echo -e "\e[32mcron 安装完成！\e[0m"
                    else
                        echo -e "\e[31mcron 安装失败！\e[0m"
                    fi
                fi
                if ! command -v socat &> /dev/null; then
                    echo "正在安装 socat..."
                    if sudo apt install -y socat; then
                        echo -e "\e[32msocat 安装完成！\e[0m"
                    else
                        echo -e "\e[31msocat 安装失败！\e[0m"
                    fi
                fi
                if curl https://get.acme.sh | sh -s email="$email"; then
                    echo -e "\e[32macme.sh 安装完成！\e[0m"
                else
                    echo -e "\e[31macme.sh 安装失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            2)
                while true; do
                    read -p "请输入域名: " domain
                    if ~/.acme.sh/acme.sh --issue --standalone -d "$domain"; then
                        echo -e "\e[32m证书申请成功！\e[0m"
                    else
                        echo -e "\e[31m证书申请失败，请检查域名是否正确并重试。\e[0m"
                    fi
                break
                done
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            3)
                ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [[ $? -eq 0 ]]; then
                    echo -e "\e[32m已切换至Let's Encrypt服务！\e[0m"
                else
                    echo -e "\e[31m切换至Let's Encrypt服务失败，请检查是否正确安装acme.sh并确保网络连接正常。\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            4)
                read -p "请输入域名: " domain
                read -p "请输入证书安装路径（默认: /path/to）: " install_path
                install_path=${install_path:-/path/to}
                if mkdir -p "$install_path" && \
                    ~/.acme.sh/acme.sh --installcert -d "$domain" \
                    --key-file "$install_path/private.key" --fullchain-file "$install_path/fullchain.crt" && \
                    sudo chmod 644 "$install_path/fullchain.crt" "$install_path/private.key"; then
                   echo -e "\e[32m证书安装完成！路径: $install_path\e[0m"
                   else
                   echo -e "\e[31m证书安装失败，请检查输入。\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            5)
                if ~/.acme.sh/acme.sh --uninstall; then
                    echo -e "\e[32macme.sh 已卸载。\e[0m"
                else
                    echo -e "\e[31macme.sh 卸载失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;            
            *)
                echo -e "\e[31m无效选项，请重新输入。\e[0m"
                ;;
        esac
    done
}

# 安装Xray
install_xray() {
    while true; do
        echo "========================================="
    echo -e "               \e[1;32m安装Xray\e[0m       "
        echo "========================================="
        echo "1) VLESS-WS-TLS"
        echo "2) VLESS-TCP-REALITY"
        echo "3) 卸载服务"
        echo "========================================="
        read -p "请输入数字 [1-2] 选择 (默认回车退出)：" opt_choice
        case "$opt_choice" in
            1) install_xray_tls ;;
            2) install_xray_reality ;;
            "") 
                return
                ;;            
            3)
                if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge; then
                echo -e "\e[32mXray已卸载。\e[0m"
                else
                echo -e "\e[31mXray卸载失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;                        
            *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
        esac
    done
}

# 安装VLESS-WS-TLS
install_xray_tls() {
    while true; do
        echo "========================================="
        echo -e "               \e[1;34mVLESS-WS-TLS\e[0m   "
        echo "========================================="
        echo "1) 安装升级"
        echo "2) 编辑配置"
        echo "3) 重启服务"
        echo "========================================="
        read -p "请输入数字 [1-3] 选择功能 (默认回车退出)：" xray_choice
        case "$xray_choice" in
            1)
               if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install && \
                   sudo curl -o /usr/local/etc/xray/config.json "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-TCP-TLS-WS%20(recommended)/config_server.jsonc"; then
                echo -e "\e[32mXray 安装升级完成！\e[0m"
                echo "以下是uuid："
                echo -e "\e[34m$(xray uuid)\e[0m"
                else
                echo -e "\e[31mXray 安装升级失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            2)
                echo -e "\e[33m提示：将UUID填入配置文件中。若已执行成功默认设置的“安装证书”则证书路径无须修改。\e[0m"
                read -n 1 -s -r -p "按任意键继续..."                
                if ! command -v nano >/dev/null 2>&1; then
                sudo apt update >/dev/null 2>&1 && sudo apt install -y nano >/dev/null 2>&1
                fi
                if ! command -v nano >/dev/null 2>&1; then
                echo -e "\e[31m错误：无法安装或找到 nano！\e[0m" >&2
                exit 1
                fi
                sudo nano /usr/local/etc/xray/config.json
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            3)
                CONFIG_PATH="/usr/local/etc/xray/config.json"
                extract_field() {
                    local pattern="$1"
                    local match="$2"
                    grep -aPo "\"$pattern\":\s*$match" "$CONFIG_PATH" | head -n 1 | sed -E "s/\"$pattern\":\s*//;s/^\"//;s/\"$//"
}
                extract_list_field() {
                    local list_parent="$1"
                    local list_field="$2"
                    grep -aPoz "\"$list_parent\":\s*\[\s*\{[^}]*\}\s*\]" "$CONFIG_PATH" | grep -aPo "\"$list_field\":\s*\"[^\"]*\"" | head -n 1 | sed -E "s/\"$list_field\":\s*\"([^\"]*)\"/\1/"
}
                get_domain_from_cert() {
                    local cert_file="$1"
                    openssl x509 -in "$cert_file" -text -noout | grep -aPo "DNS:[^,]*" | sed 's/DNS://' | head -n 1 ||
                    openssl x509 -in "$cert_file" -text -noout | grep -aPo "CN=[^ ]*" | sed 's/CN=//'
}
                get_public_ip() {
                    ipv4=$(curl -s https://api.ipify.org)
                    if [[ -n "$ipv4" ]]; then
                    echo "$ipv4"
                    else
                    curl -s -6 https://api64.ipify.org || echo "127.0.0.1"
                    fi
}
                while true; do
                    sudo systemctl restart xray
                    sleep 2
                    if ! systemctl is-active --quiet xray; then
                        echo -e "\e[31m未能启动 xray 服务，请检查日志。\e[0m"
                        systemctl status xray --no-pager
                        break
                    else
                        echo -e "\e[32mxray已启动！\e[0m"
                    fi
                UUID=$(extract_list_field "clients" "id")
                PORT=$(extract_field "port" "\d+")
                WS_PATH=$(extract_field "path" "\"[^\"]*\"")
                TLS=$(extract_field "security" "\"[^\"]*\"")
                CERT_PATH=$(extract_list_field "certificates" "certificateFile")
                if [[ -z "$CERT_PATH" ]]; then
                    echo -e "\e[31m未能找到证书路径。\e[0m"
                    break
                fi
                DOMAIN=$(get_domain_from_cert "$CERT_PATH")
                SNI=${DOMAIN:-"your.domain.net"}
                HOST=${DOMAIN:-"your.domain.net"}
                ADDRESS=$(get_public_ip)
                WS_PATH=${WS_PATH:-"/"}
                TLS=${TLS:-"tls"}
                PORT=${PORT:-"443"}
                vless_uri="vless://${UUID}@${ADDRESS}:${PORT}?encryption=none&security=${TLS}&sni=${SNI}&type=ws&host=${HOST}&path=${WS_PATH}#Xray"
                echo "VLESS链接如下"
                echo -e "\e[34m$vless_uri\e[0m"
                break
                done
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;                                   
            *)
                echo -e "\e[31m无效选项，请重新输入。\e[0m"
                ;;
        esac
    done
}

# 安装VLESS-TCP-REALITY
install_xray_reality() {
    while true; do
        echo "========================================="
        echo -e "               \e[1;34mVLESS-TCP-REALITY\e[0m   "
        echo "========================================="
        echo "1) 安装升级"
        echo "2) 编辑配置"
        echo "3) 重启服务"
        echo "========================================="
        read -p "请输入数字 [1-3] 选择(默认回车退出)：" xray_choice
        case "$xray_choice" in
            1)
               if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install && \
                  sudo curl -o /usr/local/etc/xray/config.json "https://raw.githubusercontent.com/XTLS/Xray-examples/refs/heads/main/VLESS-TCP-XTLS-Vision-REALITY/config_server.jsonc"; then
                echo -e "\e[32mXray 安装升级完成！\e[0m"
                echo "以下是UUID："
                echo -e "\e[34m$(xray uuid)\e[0m"
                echo "以下是私钥："
                keys=$(xray x25519)
                export PRIVATE_KEY=$(echo "$keys" | head -n 1 | awk '{print $3}' | sed 's/^-//')
                export PUBLIC_KEY=$(echo "$keys" | tail -n 1 | awk '{print $3}' | sed 's/^-//')
                echo -e "\e[34m$PRIVATE_KEY\e[0m"                
                echo "以下是ShortIds："                
                echo -e "\e[34m$(openssl rand -hex 8)\e[0m"
                else
                echo -e "\e[31mXray 安装升级失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            2)
                echo -e "\e[33m提示：将UUID、目标网站及私钥填入配置文件中，ShortIds非必须。\e[0m"
                read -n 1 -s -r -p "按任意键继续..."                                
                if ! command -v nano >/dev/null 2>&1; then
                sudo apt update >/dev/null 2>&1 && sudo apt install -y nano >/dev/null 2>&1
                fi
                if ! command -v nano >/dev/null 2>&1; then
                echo -e "\e[31m错误：无法安装或找到 nano！\e[0m" >&2
                exit 1
                fi
                sudo nano /usr/local/etc/xray/config.json
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            3)
                CONFIG_PATH="/usr/local/etc/xray/config.json"
                remove_spaces_and_quotes() {
                    echo "$1" | sed 's/[[:space:]]*$//;s/^ *//;s/^"//;s/"$//'
}
                extract_field() {
                    local pattern=$1
                    local match=$2
                    grep -aPo "\"$pattern\":\s*$match" "$CONFIG_PATH" | head -n 1 | sed -E "s/\"$pattern\":\s*//;s/^\"//;s/\"$//"
}
                extract_server_name() {
                    local result=$(grep -aA 2 "\"serverNames\": \[" "$CONFIG_PATH" | awk 'NR==2{gsub(/^\s+|\s*\/\/.*$/,"");split($0,a,","); for (i in a) {gsub(/^[\"\s]+|[\"\s]+$/,"",a[i]);printf "%s ",a[i]}}')
                    if [[ -n "$result" ]]; then
                        remove_spaces_and_quotes "$result"
                    fi
}
                extract_list_field() {
                    local list_parent=$1
                    local list_field=$2
                    if [[ "$list_field" == "shortIds" || "$list_field" == "serverNames" ]]; then
                        local result=$(grep -aA 2 "\"$list_field\": \[" "$CONFIG_PATH" | awk 'NR==2{gsub(/^\s+|\s*\/\/.*$/,"");split($0,a,","); for (i in a) {gsub(/^[\"\s]+|[\"\s]+$/,"",a[i]);printf "%s ",a[i]}}')
                        if [[ -n "$result" ]]; then
                            remove_spaces_and_quotes "$result"
                        fi
                    else
                        grep -aPoz "\"$list_parent\":\s*\[\s*\{[^}]*\}\s*\]" "$CONFIG_PATH" | grep -aPo "\"$list_field\":\s*\"[^\"]*\"" | head -n 1 | sed -E "s/\"$list_field\":\s*\"([^\"]*)\"/\1/"
                    fi
}
                get_public_ip() {
                    ipv4=$(curl -s https://api.ipify.org)
                    if [[ -n "$ipv4" ]]; then
                    echo "$ipv4"
                    else
                    curl -s -6 https://api64.ipify.org || echo "127.0.0.1"
                    fi
}
                while true; do
                    sudo systemctl restart xray
                    sleep 2
                    if ! systemctl is-active --quiet xray; then
                       echo -e "\e[31m未能启动 xray 服务，请检查日志。\e[0m"
                       systemctl status xray --no-pager
                       break
                    else
                        echo -e "\e[32mxray已启动！\e[0m"
                    fi
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
                vless_uri="vless://${UUID}@${ADDRESS}:${PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${SNI}&fp=chrome&sid=${SID}&type=tcp&headerType=none#Xray"
                echo "VLESS链接如下："
                echo -e "\e[34m$vless_uri\e[0m"
                echo "以下是公钥："
                echo -e "\e[34m$PUBLIC_KEY\e[0m"
                echo -e "\e[33m提示：将公钥填入客户端中。\e[0m"
                break
                done
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;                        
            *)
                echo -e "\e[31m无效选项，请重新输入。\e[0m"
                ;;
        esac
    done
}

# 安装Hysteria2
install_hysteria2() {
    while true; do    
        echo "========================================="
        echo -e "           \e[1;32m安装Hysteria2\e[0m  "
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
                if bash <(curl -fsSL https://get.hy2.sh/) && \
                   sudo systemctl enable --now hysteria-server.service && \
                   sysctl -w net.core.rmem_max=16777216 && \
                   sysctl -w net.core.wmem_max=16777216; then
                echo -e "\e[32mhysteria2 安装升级完成！\e[0m"
                else
                echo -e "\e[31mhysteria2 安装升级失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            2)
                echo -e "\e[33m提示：将域名填入配置文件中。\e[0m"
                read -n 1 -s -r -p "按任意键继续..."                                                
                if ! command -v nano >/dev/null 2>&1; then
                sudo apt update >/dev/null 2>&1 && sudo apt install -y nano >/dev/null 2>&1
                fi
                if ! command -v nano >/dev/null 2>&1; then
                echo -e "\e[31m错误：无法安装或找到 nano！\e[0m" >&2
                exit 1
                fi
                sudo nano /etc/hysteria/config.yaml
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            3)
                config_file="/etc/hysteria/config.yaml"
                get_domain_from_cert() {
                    local cert_file=$1
                    openssl x509 -in "$cert_file" -text -noout | grep -Po "DNS:[^,]*" | head -n 1 | sed 's/DNS://' ||
                    openssl x509 -in "$cert_file" -text -noout | grep -Po "CN=[^ ]*" | sed 's/CN=//'
}
                if [ ! -f "$config_file" ]; then
                    echo -e "\e[31m未能找到配置文件。\e[0m"
                    break
                fi
                while true; do
                    sudo systemctl restart hysteria-server.service
                    sleep 2
                    if ! systemctl is-active --quiet hysteria-server.service; then
                        echo -e "\e[31m未能启动 hysteria 服务，请检查日志。\e[0m"
                        sudo systemctl status hysteria-server.service --no-pager
                        break
                    else
                        echo -e "\e[32mhysteria已启动！\e[0m"
                    fi
                port=$(grep "^listen:" "$config_file" | awk -F: '{print $3}' || echo "443")
                password=$(grep "^  password:" "$config_file" | awk '{print $2}')
                domain=$(grep "domains:" "$config_file" -A 1 | tail -n 1 | tr -d " -")
                if [ -z "$domain" ]; then
                    cert_path=$(grep "cert:" "$config_file" | awk '{print $2}' | tr -d '"')
                    if [ -z "$cert_path" ] || [ ! -f "$cert_path" ]; then
                        echo -e "\e[31m没有找到域名或证书。\e[0m"
                        break
                    fi
                    domain=$(get_domain_from_cert "$cert_path")
                    if [ -z "$domain" ]; then
                        echo -e "\e[31m从证书中提取域名失败。\e[0m"
                        break
                    fi
                fi
                hysteria2_uri="hysteria2://$password@$domain:$port?insecure=0#hysteria"
                echo "hysteria2 链接如下："
                echo -e "\e[34m$hysteria2_uri\e[0m"
                break
                done
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            4)
                default_redirect_port=443
                default_start_port=60000
                default_end_port=65535
                config_file="/etc/hysteria/config.yaml"
                redirect_port=$(
                if [[ -f "$config_file" ]]; then
                    grep 'listen:' "$config_file" | awk -F':' '{print $NF}'
                fi
)
                [[ -z "$redirect_port" || ! "$redirect_port" =~ ^[0-9]+$ || "$redirect_port" -lt 1 || "$redirect_port" -gt 65535 ]] && redirect_port="$default_redirect_port"
                read -p "请输入起始端口号 (按 Enter 使用默认值 60000): " start_port
                [[ -z "$start_port" ]] && start_port="$default_start_port"
                [[ "$start_port" =~ ^[0-9]+$ && "$start_port" -ge 1 && "$start_port" -le 65535 ]] || { echo -e "\e[31m起始端口号无效, 使用默认值 60000\e[0m"; start_port="$default_start_port"; }
                read -p "请输入结束端口号 (按 Enter 使用默认值 65535): " end_port
                [[ -z "$end_port" ]] && end_port="$default_end_port"
                [[ "$end_port" =~ ^[0-9]+$ && "$end_port" -ge 1 && "$end_port" -le 65535 && "$end_port" -ge "$start_port" ]] || { echo -e "\e[31m结束端口号无效，使用默认值 65535\e[0m"; end_port="$default_end_port"; }
                interfaces=($(ip -o link | awk -F': ' '{if ($2 != "lo") print $2}'))
                [[ ${#interfaces[@]} -eq 0 ]] && { echo -e "\e[31m未找到网络接口，无法执行 iptables 命令。\e[0m"; exit 1; }
                selected_interface="${interfaces[0]}"
                iptables_command="iptables -t nat -A PREROUTING -i $selected_interface -p udp --dport $start_port:$end_port -j REDIRECT --to-ports $redirect_port"
                if eval "$iptables_command"; then
                echo -e "\e[32m端口跳跃设置成功!\e[0m"
                else
                echo -e "\e[31miptables命令执行失败。\e[0m"
                exit 1
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            5)
               if bash <(curl -fsSL https://get.hy2.sh/) --remove && \
                rm -rf /etc/hysteria &&
                userdel -r hysteria &&
                rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server.service &&
                rm -f /etc/systemd/system/multi-user.target.wants/hysteria-server@*.service &&
                systemctl daemon-reload; then
                echo -e "\e[32mhysteria2 已卸载。\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;            
            *)
                echo -e "\e[31m无效选项，请重新输入。\e[0m"
                ;;
        esac
    done
}

# 安装sing-box
install_sing-box() {
    while true; do    
        echo "========================================="
        echo -e "           \e[1;32m安装sing-box\e[0m  "
        echo "========================================="
        echo "1) 安装升级"
        echo "2) 编辑配置"
        echo "3) 重启服务"
        echo "4) 卸载服务"
        echo "========================================="
        read -p "请输入数字 [1-4] 选择 (默认回车退出)：" singbox_choice
        case "$singbox_choice" in
            1)
               if bash <(curl -fsSL https://sing-box.app/deb-install.sh) && \
                  sudo curl -L -o /etc/sing-box/config.json "https://raw.githubusercontent.com/sezhai/VPS-Script/refs/heads/main/extras/sing-box/config.json"; then
                   echo -e "\e[32msing-box 安装升级成功！\e[0m"
               else
                   echo -e "\e[31msing-box 安装升级失败！\e[0m"
               fi
               read -n 1 -s -r -p "按任意键返回..."
               echo
               ;;
            2)
                echo -e "\e[33m提示：根据提示修改配置文件。\e[0m"
                read -n 1 -s -r -p "按任意键继续..."                                                
                if ! command -v nano >/dev/null 2>&1; then
                sudo apt update >/dev/null 2>&1 && sudo apt install -y nano >/dev/null 2>&1
                fi
                if ! command -v nano >/dev/null 2>&1; then
                echo -e "\e[31m无法安装或找到 nano。\e[0m" >&2
                exit 1
                fi
                sudo nano /etc/sing-box/config.json
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            3)
                CONFIG_PATH="/etc/sing-box/config.json"
                sudo systemctl restart sing-box
                sleep 2
                if ! systemctl is-active --quiet sing-box; then
                    echo -e "\e[31m未能启动 sing-box 服务，请检查日志。\e[0m"
                    systemctl status sing-box --no-pager
                    exit 1
                else
                    echo -e "\e[32msing-box已启动！\e[0m"
                fi
                get_ip() {
                    curl -s https://api.ipify.org || echo "127.0.0.1"
                }
                urlencode() {
                    local s="$1" ch
                    for ((i=0; i<${#s}; i++)); do
                        ch="${s:i:1}"
                        case "$ch" in
                            [a-zA-Z0-9.~_-]) printf '%s' "$ch" ;;
                            *) printf '%%%02X' "'$ch" ;;
                        esac
                    done
                }
                ip=$(get_ip)
                vmess_uuid=$(grep -Pzo '(?s)"tag": "vmess".*?uuid":\s*"\K[^"]+' "$CONFIG_PATH" | tr -d '\0')
                vmess_port=$(grep -Pzo '(?s)"tag": "vmess".*?listen_port":\s*\K[0-9]+' "$CONFIG_PATH" | tr -d '\0')
                vmess_path=$(grep -Pzo '(?s)"tag": "vmess".*?path":\s*"\K[^"]+' "$CONFIG_PATH" | tr -d '\0')
                vmess_host=$(grep -Pzo '(?s)"tag": "vmess".*?server_name":\s*"\K[^"]+' "$CONFIG_PATH" | tr -d '\0')
                vmess_sni="$vmess_host"
                vmess_json=$(cat <<EOF
                {
                "v": "2",
                "ps": "vmess",
                "add": "$ip",
                "port": "$vmess_port",
                "id": "$vmess_uuid",
                "aid": "0",
                "scy": "auto",
                "net": "ws",
                "type": "none",
                "host": "$vmess_host",
                "path": "$vmess_path",
                "tls": "tls",
                "sni": "$vmess_sni",
                "alpn": "http/1.1",
                "fp": "chrome"
                }
EOF
)
                vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w0)"
                vless_uuid=$(grep -Pzo '(?s)"tag": "reality".*?uuid":\s*"\K[^"]+' "$CONFIG_PATH" | tr -d '\0')
                vless_port=$(grep -Pzo '(?s)"tag": "reality".*?listen_port":\s*\K[0-9]+' "$CONFIG_PATH" | tr -d '\0')
                server_ip=$(curl -s icanhazip.com)
                vless_sni=$(grep -Pzo '(?s)"tag": "reality".*?server_name":\s*"\K[^"]+' "$CONFIG_PATH" | tr -d '\0')
                vless_sid=$(grep -Pzo '(?s)"tag": "reality".*?short_id":\s*\[\s*"\K[^"]+' "$CONFIG_PATH" | tr -d '\0')
                vless_link="vless://$vless_uuid@$server_ip:$vless_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vless_sni&fp=chrome&sid=$vless_sid&type=tcp&headerType=none#reality"
                get_domain_from_cert() {
                    local cert_file=$1
                    openssl x509 -in "$cert_file" -text -noout | grep -Po "DNS:[^,]*" | head -n 1 | sed 's/DNS://' ||
                    openssl x509 -in "$cert_file" -text -noout | grep -Po "CN=[^ ]*" | sed 's/CN=//'
                }
                h2_pass_raw=$(grep -Pzo '(?s)"tag": "hysteria2".*?password":\s*"\K[^"]+' "$CONFIG_PATH" | tr -d '\0')
                h2_pass=$(urlencode "$h2_pass_raw")
                h2_port=$(grep -Pzo '(?s)"tag": "hysteria2".*?listen_port":\s*\K[0-9]+' "$CONFIG_PATH" | tr -d '\0')
                cert_path=$(grep -Pzo '(?s)"tag": "hysteria2".*?"certificate_path":\s*"\K[^"]+' "$CONFIG_PATH" | tr -d '\0')
                if [ -z "$cert_path" ] || [ ! -f "$cert_path" ]; then
                    echo -e "\e[31m没有找到证书路径。\e[0m"
                    exit 1
                fi
                h2_domain=$(get_domain_from_cert "$cert_path")
                if [ -z "$h2_domain" ]; then
                    echo -e "\e[31m从证书中提取SNI失败。\e[0m"
                    exit 1
                fi
                h2_link="hysteria2://$h2_pass@$ip:$h2_port?sni=$h2_domain&insecure=0#hysteria2"
                echo "vmess 链接如下："
                echo -e "\e[34m$vmess_link\e[0m"
                echo "reality 链接如下："
                echo -e "\e[34m$vless_link\e[0m"
                echo "hysteria2 链接如下："
                echo -e "\e[34m$h2_link\e[0m"
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            4)
               if systemctl disable --now sing-box && rm -f /usr/local/bin/sing-box /etc/systemd/system/sing-box.service && rm -rf /var/lib/sing-box /etc/sing-box; then
                echo -e "\e[32msing-box 已卸载。\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;            
            *)
                echo -e "\e[31m无效选项，请重新输入。\e[0m"
                ;;
        esac
    done
}

# 安装1Panel
install_1panel() {
    while true; do
        echo "========================================="
        echo -e "               \e[1;32m安装1Panel\e[0m "
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
                if curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && sudo bash quick_start.sh; then
                echo -e "\e[32m1Panel 安装完成！\e[0m"
                else
                echo -e "\e[31m1Panel 安装失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            2)
                1pctl user-info
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            3)
                if sudo apt install ufw; then
                echo -e "\e[32mufw 安装完成！\e[0m"
                else
                echo -e "\e[31mufw 安装失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            4)
                if sudo apt remove -y ufw && sudo apt purge -y ufw && sudo apt autoremove -y; then
                echo -e "\e[32mufw 卸载完成。\e[0m"
                else
                echo -e "\e[31mufw 卸载失败！\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            5)
                if sudo systemctl stop 1panel && sudo 1pctl uninstall && sudo rm -rf /var/lib/1panel /etc/1panel /usr/local/bin/1pctl && sudo journalctl --vacuum-time=3d &&
                    sudo systemctl stop docker && sudo apt-get purge -y docker-ce docker-ce-cli containerd.io && \
                    sudo find / \( -name "1panel*" -or -name "docker*" -or -name "containerd*" -or -name "compose*" \) -exec rm -rf {} + && \
                    sudo groupdel docker; then
                echo -e "\e[32m1Panel 卸载完成。\e[0m"
                fi
                read -n 1 -s -r -p "按任意键返回..."
                echo
                ;;
            "") 
                return
                ;;            
            *)
                echo -e "\e[31m无效选项，请重新输入。\e[0m"
                ;;
        esac
    done    
}

# -----------------------------------------------------------------------------
# 主脚本循环
# -----------------------------------------------------------------------------

while true; do
    display_main_menu
    read -p "请输入数字 [1-9] 选择(默认回车退出)：" choice
    if [[ -z "$choice" ]]; then
      echo -e "\e[32m退出脚本，感谢使用！\e[0m"
      exit 0
    fi
    case "$choice" in
        1) view_vps_info ;;
        2) display_system_optimization_menu ;;
        3) common_tools ;;
        4) install_package;;
        5) apply_certificate ;;
        6) install_xray ;;
        7) install_hysteria2 ;;
        8) install_sing-box;;
        9) install_1panel ;;
        *)
            echo -e "\e[31m无效选项，请输入数字 1-9 或直接回车退出！\e[0m"
            ;;
    esac
done
