# Nikki Mihomo Smart内核更新工具

这个脚本用于自动检查、下载和更新Nikki使用的Mihomo Smart内核，适用于OpenWrt系统。

## 功能特点

- **自动检测系统架构**：自动识别系统架构（x86_64/arm64/armv7/mips等），下载对应版本
- **自动检查更新**：支持手动检查和计划任务自动更新
- **备份与回滚**：自动备份当前内核，支持一键回滚
- **权限自动修复**：安装和检测时会自动补齐 `mihomo` 的执行权限
- **简洁界面**：提供直观的菜单操作

## 使用方法

### 基本使用

脚本来源：

- 项目页面：`https://github.com/666OS/YYDS/tree/main/JS`
- 下载地址：`https://raw.githubusercontent.com/qqrrooty/smartcore/refs/heads/main/smartcore.sh`

1. 下载脚本到OpenWrt设备并运行
   ```
   wget -O smartcore.sh --no-check-certificate https://raw.githubusercontent.com/qqrrooty/smartcore/refs/heads/main/smartcore.sh && chmod +x smartcore.sh && ./smartcore.sh
   ```
   国内CDN加速
   ```
   wget -O smartcore.sh --no-check-certificate https://cdn.gh-proxy.com/https://raw.githubusercontent.com/qqrrooty/smartcore/refs/heads/main/smartcore.sh && chmod +x smartcore.sh && ./smartcore.sh
   ```
   
2. 运行脚本：`./smartcore.sh`

### 命令行参数

脚本支持以下命令行参数：

- `--auto` 或 `-a`：自动检查并更新内核（适合计划任务）
- `--debug` 或 `-d`：开启调试模式
- `--help` 或 `-h`：显示帮助信息
- `--changelog` 或 `-c`：仅显示最新更新日志

### 菜单选项

脚本提供以下操作选项：

1. **检查并更新内核**：检查新版本并直接安装
2. **仅检查更新**：只检查是否有新版本可用
3. **回滚到上一版本**：恢复到之前备份的版本
4. **查看最新更新日志**：显示当前发布页中的最新一条日志
0. **退出**：退出脚本

## 自动更新

如果需要定期自动检查和更新内核，可以将脚本添加到计划任务：

```
# 每天凌晨3点检查并更新内核
0 3 * * * ./smartcore.sh --auto >> /tmp/smartcore_update.log 2>&1
```

## 注意事项

- 脚本运行需要root权限
- 请确保设备有足够的存储空间
- 脚本默认将内核文件安装到 `/usr/bin/mihomo`
- 更新前会自动备份当前内核到 `/usr/bin/mihomo.bak`
- 回滚前会将当前内核额外备份到 `/usr/bin/mihomo.current`
- 更新完成后会自动重启Nikki服务

## 更新日志说明

- 日志页内容来自 Mihomo 的 GitHub 发布页
- 脚本默认读取 `Prerelease-Alpha` 标签页
- 终端内只显示最新一条更新日志，并过滤部分 GitHub 页面噪音文本

## 已知问题

- 在某些网络环境下，可能无法访问GitHub，导致更新检查或日志抓取失败
- 如果系统缺少 `curl`、`wget`、`gzip` 等命令，更新过程会失败

## 故障排除

如果遇到问题，请检查：

1. 网络连接是否正常
2. 是否有足够的存储空间
3. Nikki是否正确安装
4. `/usr/bin/mihomo` 是否存在且有执行权限
5. `/etc/init.d/nikki restart` 是否可以正常执行

## 许可证

此脚本是开源的，欢迎自由使用和修改。
