# Nikki Mihomo Smart内核更新工具

这个脚本用于自动检查、下载和更新Nikki使用的Mihomo Smart内核，并支持手动更新LightGBM模型，适用于OpenWrt系统。

## 功能特点

- **自动检测系统架构**：自动识别系统架构（x86_64/arm64/armv7/mips等），下载对应版本
- **自动检查更新**：支持手动检查和计划任务自动更新，自动更新可指定与手动菜单一致的版本变体
- **备份与回滚**：自动备份当前内核，支持一键回滚
- **模型更新**：可选择默认、中型或大型LightGBM模型，下载到 `/etc/nikki/run/Model.bin`，自动备份旧模型并重启Nikki
- **权限自动修复**：安装和检测时会自动补齐 `mihomo` 的执行权限
- **快捷命令**：安装后直接输入 `smart` 打开脚本
- **旧版清理**：迁移到 `smart` 后会清理旧版 `smartcore.sh --auto` 定时任务和旧脚本文件
- **简洁界面**：提供直观的菜单操作

## 使用方法

### 基本使用

脚本来源：

- 项目页面：`https://github.com/666OS/YYDS/tree/main/JS`
- 下载地址：`https://raw.githubusercontent.com/qqrrooty/smartcore/refs/heads/main/smartcore.sh`

1. 下载脚本到OpenWrt设备并运行
   ```
   wget -O /usr/bin/smart --no-check-certificate https://raw.githubusercontent.com/qqrrooty/smartcore/refs/heads/main/smartcore.sh && chmod +x /usr/bin/smart && smart
   ```
   国内CDN加速
   ```
   wget -O /usr/bin/smart --no-check-certificate https://cdn.gh-proxy.com/https://raw.githubusercontent.com/qqrrooty/smartcore/refs/heads/main/smartcore.sh && chmod +x /usr/bin/smart && smart
   ```
   
2. 运行脚本：`smart`

### 命令行参数

脚本支持以下命令行参数：

- `--auto` 或 `-a`：自动检查并更新内核（适合计划任务）
- `--variant-choice <编号>` 或 `--variant <编号>`：指定版本变体编号，和手动菜单一致
- `--debug` 或 `-d`：开启调试模式
- `--help` 或 `-h`：显示帮助信息
- `--changelog` 或 `-c`：仅显示最新更新日志

示例：

```
smart --auto --variant-choice 2
smart --auto --variant 4
```

### 菜单选项

脚本提供以下操作选项：

1. **检查并更新内核**：检查新版本并直接安装
2. **仅检查更新**：只检查是否有新版本可用
3. **回滚到上一版本**：恢复到之前备份的版本
4. **查看最新更新日志**：显示当前发布页中的最新一条日志
5. **设置自动更新**：启用/关闭自动更新，并设置执行时间和版本变体
6. **更新 Model.bin**：选择默认、中型或大型模型，下载并安装到Nikki运行目录
0. **退出**：退出脚本

## 更新 Model.bin

运行 `smart`，选择 **6. 更新 Model.bin**，再选择模型：

| 选项 | 模型 | 下载文件 |
| --- | --- | --- |
| 1 | 默认模型 | [Model.bin](https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model.bin) |
| 2 | 中型模型 | [Model-middle.bin](https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model-middle.bin) |
| 3 | 大型模型 | [Model-large.bin](https://github.com/vernesong/mihomo/releases/download/LightGBM-Model/Model-large.bin) |
| 0 | 返回主菜单 | 不下载或修改模型 |

- 每次选择一个模型，三种文件均以 **`Model.bin`** 为文件名安装到 **`/etc/nikki/run/`**，供内核加载。
- 下载优先直连GitHub，失败后使用脚本配置的GitHub加速地址。
- 下载在目标目录的临时文件中完成，通过基本的LightGBM格式检查后才替换当前模型；下载失败、空文件或格式检查失败时保留原模型。
- 已有模型会备份到 `/etc/nikki/run/Model.bin.bak`。模型内容相同时跳过替换和重启。
- 安装成功后自动重启Nikki；如果重启失败，脚本会提示手动检查服务，新模型仍保留在目标路径。
- 菜单中的“回滚到上一版本”和现有自动更新计划任务仍针对内核。需要恢复模型时可手动执行：

  ```sh
  cp /etc/nikki/run/Model.bin.bak /etc/nikki/run/Model.bin && /etc/init.d/nikki restart
  ```

## 自动更新

可以在脚本菜单中进入“设置自动更新”，开启时会先设置时间，再选择与手动更新一致的版本变体。
新版会使用 `/usr/bin/smart --auto --variant-choice 编号` 写入计划任务，并自动清理旧版 `smartcore.sh --auto` 定时任务。

x86_64 版本变体示例：

1. 标准版本 `mihomo-linux-amd64`
2. 兼容版本 `mihomo-linux-amd64-compatible`
3. Go 1.20版本 `mihomo-linux-amd64-go120`
4. Go 1.23版本 `mihomo-linux-amd64-go123`
5. 兼容Go 1.20版本 `mihomo-linux-amd64-compatible-go120`
6. 兼容Go 1.23版本 `mihomo-linux-amd64-compatible-go123`

也可以手动添加计划任务：

```
# 每天凌晨3点检查并更新内核
0 3 * * * /usr/bin/smart --auto --variant-choice 2 >> /tmp/smartcore_update.log 2>&1
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
