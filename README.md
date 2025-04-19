#  VPS一键管理脚本

## 自用的vps常用命令脚本，适用于debian与ubuntu系统，目前集成以下功能：

- 查看系统配置信息；
- 系统优化：更新、清理、开启BBR及ROOT登录等；
- 常用工具：查找、删除、关闭进程、开启端口等；
- 常用软件包安装与卸载；
- 域名证书申请；
- Xray官方安装、配置及卸载；
- Hysteria2官方安装、配置及卸载；
- Sing-Box官方安装、配置及卸载；
- 1Panel官方安装、配置及卸载；
- 其他功能是否添加看个人需要。

## 直接使用命令

```Bash
bash <(curl -sL https://raw.githubusercontent.com/sezhai/vps-script/refs/heads/main/one.sh)
```

## 下载使用命令

### 下载
```Bash
bash -c 'curl -sL https://raw.githubusercontent.com/sezhai/vps-script/refs/heads/main/one.sh -o /usr/local/sbin/one && chmod +x /usr/local/sbin/one && /usr/local/sbin/one'
```
### 运行
```Bash
one
```
### 卸载
```Bash
sudo rm -f /usr/local/sbin/one
```





