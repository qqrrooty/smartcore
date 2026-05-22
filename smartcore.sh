#!/bin/sh

# Mihomo Smart内核更新脚本
# 根据系统架构自动下载对应的mihomo Smart内核并重启Nikki服务

# 错误处理
set -e
trap 'echo "错误: 脚本执行失败，行 $LINENO"; exit 1' ERR

# 全局变量
NIKKI_DIR="/etc/nikki"
CORE_DIR="/usr/bin"
CORE_PATH="${CORE_DIR}/mihomo"
CORE_BACKUP_PATH="${CORE_PATH}.bak"
CORE_CURRENT_PATH="${CORE_PATH}.current"
SERVICE_NAME="nikki"
SERVICE_SCRIPT="/etc/init.d/${SERVICE_NAME}"
TEMP_DIR="/tmp/smartcore_temp"
SOURCE_REPO="vernesong/mihomo" # 默认使用vernesong镜像版本
VERSION_TAG="Prerelease-Alpha"
OS="linux"
CHANGELOG_FILE="${TEMP_DIR}/changelog.txt"
SCRIPT_VERSION="1.1.6" # 脚本版本号
AUTO_UPDATE_SCHEDULE="0 3 * * *"
AUTO_UPDATE_LOG="/tmp/smartcore_update.log"
GITHUB_ACCELERATOR="${SMARTCORE_GITHUB_ACCELERATOR:-https://cdn.gh-proxy.com/}"
GITHUB_ACCELERATOR_CONNECT_TIMEOUT="${SMARTCORE_GITHUB_ACCELERATOR_CONNECT_TIMEOUT:-15}"
GITHUB_ACCELERATOR_MAX_TIME="${SMARTCORE_GITHUB_ACCELERATOR_MAX_TIME:-60}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 日志函数
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 生成GitHub加速链接
accelerate_github_url() {
  TARGET_URL="$1"

  case "$TARGET_URL" in
    https://github.com/*|https://raw.githubusercontent.com/*|https://api.github.com/*)
      if [ -n "$GITHUB_ACCELERATOR" ]; then
        printf '%s%s\n' "${GITHUB_ACCELERATOR%/}/" "$TARGET_URL"
        return 0
      fi
      ;;
  esac

  return 1
}

# curl封装：直连失败后自动尝试GitHub加速
curl_with_accelerator_fallback() {
  CURL_OUTPUT="$1"
  shift
  CURL_URL=""

  for CURL_ARG in "$@"; do
    case "$CURL_ARG" in
      http://*|https://*) CURL_URL="$CURL_ARG" ;;
    esac
  done

  if curl "$@" > "$CURL_OUTPUT"; then
    return 0
  fi

  ACCELERATED_URL=$(accelerate_github_url "$CURL_URL" 2>/dev/null || echo "")
  if [ -n "$ACCELERATED_URL" ]; then
    log "直连失败，尝试使用GitHub加速下载..."
    log "加速地址: $ACCELERATED_URL"
    curl -s -L --connect-timeout "$GITHUB_ACCELERATOR_CONNECT_TIMEOUT" --max-time "$GITHUB_ACCELERATOR_MAX_TIME" "$ACCELERATED_URL" > "$CURL_OUTPUT"
    return $?
  fi

  return 1
}

# 下载文件：优先直连，失败后使用GitHub加速
download_file() {
  DOWNLOAD_URL="$1"
  DOWNLOAD_OUTPUT="$2"

  if command -v curl >/dev/null 2>&1 &&
     curl -L --progress-bar -o "$DOWNLOAD_OUTPUT" "$DOWNLOAD_URL"; then
    return 0
  fi

  if command -v wget >/dev/null 2>&1 &&
     wget -O "$DOWNLOAD_OUTPUT" "$DOWNLOAD_URL"; then
    return 0
  fi

  ACCELERATED_URL=$(accelerate_github_url "$DOWNLOAD_URL" 2>/dev/null || echo "")
  if [ -n "$ACCELERATED_URL" ]; then
    log "直连下载失败，尝试使用GitHub加速下载..."
    log "加速地址: $ACCELERATED_URL"

    if command -v curl >/dev/null 2>&1 &&
       curl -L --progress-bar --connect-timeout "$GITHUB_ACCELERATOR_CONNECT_TIMEOUT" --max-time "$GITHUB_ACCELERATOR_MAX_TIME" -o "$DOWNLOAD_OUTPUT" "$ACCELERATED_URL"; then
      return 0
    fi

    if command -v wget >/dev/null 2>&1 &&
       wget -O "$DOWNLOAD_OUTPUT" "$ACCELERATED_URL"; then
      return 0
    fi
  fi

  return 1
}

# 检查URL是否可访问：直连失败后使用GitHub加速
check_url_available() {
  CHECK_URL="$1"

  if curl -s -L --head --fail "$CHECK_URL" >/dev/null; then
    return 0
  fi

  ACCELERATED_URL=$(accelerate_github_url "$CHECK_URL" 2>/dev/null || echo "")
  if [ -n "$ACCELERATED_URL" ]; then
    log "直连验证失败，尝试使用GitHub加速验证..."
    curl -s -L --connect-timeout "$GITHUB_ACCELERATOR_CONNECT_TIMEOUT" --max-time "$GITHUB_ACCELERATOR_MAX_TIME" --head --fail "$ACCELERATED_URL" >/dev/null
    return $?
  fi

  return 1
}

# 获取脚本绝对路径，供计划任务使用
get_script_path() {
  if [ -n "$SCRIPT_PATH" ]; then
    return 0
  fi

  if command -v readlink >/dev/null 2>&1; then
    SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "")
  fi

  if [ -z "$SCRIPT_PATH" ]; then
    SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)
    SCRIPT_PATH="${SCRIPT_DIR}/$(basename "$0")"
  fi

  [ -n "$SCRIPT_PATH" ]
}

# 生成自动更新计划任务内容
get_auto_update_entry() {
  get_script_path || return 1
  printf '%s %s --auto >> %s 2>&1\n' "$AUTO_UPDATE_SCHEDULE" "$SCRIPT_PATH" "$AUTO_UPDATE_LOG"
}

# 获取当前自动更新计划任务
get_auto_update_cron_line() {
  get_script_path || return 1
  crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH --auto" | tail -n 1
}

# 从现有计划任务中加载自动更新时间
load_auto_update_schedule() {
  CRON_LINE=$(get_auto_update_cron_line 2>/dev/null || echo "")

  if [ -n "$CRON_LINE" ]; then
    CRON_MINUTE=$(echo "$CRON_LINE" | awk '{print $1}')
    CRON_HOUR=$(echo "$CRON_LINE" | awk '{print $2}')

    case "$CRON_MINUTE:$CRON_HOUR" in
      ''|*[^0-9:]*)
        return 1
        ;;
      *)
        AUTO_UPDATE_SCHEDULE="${CRON_MINUTE} ${CRON_HOUR} * * *"
        return 0
        ;;
    esac
  fi

  return 1
}

# 将当前自动更新计划转换为 HH:MM
get_auto_update_time_display() {
  AUTO_MINUTE=$(echo "$AUTO_UPDATE_SCHEDULE" | awk '{print $1}')
  AUTO_HOUR=$(echo "$AUTO_UPDATE_SCHEDULE" | awk '{print $2}')

  printf '%02d:%02d\n' "$AUTO_HOUR" "$AUTO_MINUTE"
}

# 让用户输入自动更新时间
prompt_auto_update_time() {
  CURRENT_TIME=$(get_auto_update_time_display)
  printf "请输入自动更新时间 [HH:MM] (当前: %s，回车保持不变): " "$CURRENT_TIME"
  read -r INPUT_TIME

  if [ -z "$INPUT_TIME" ]; then
    return 0
  fi

  case "$INPUT_TIME" in
    [0-1][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9])
      INPUT_HOUR=${INPUT_TIME%:*}
      INPUT_MINUTE=${INPUT_TIME#*:}
      INPUT_HOUR=$(echo "$INPUT_HOUR" | sed 's/^0*//')
      INPUT_MINUTE=$(echo "$INPUT_MINUTE" | sed 's/^0*//')
      [ -z "$INPUT_HOUR" ] && INPUT_HOUR=0
      [ -z "$INPUT_MINUTE" ] && INPUT_MINUTE=0
      AUTO_UPDATE_SCHEDULE="${INPUT_MINUTE} ${INPUT_HOUR} * * *"
      return 0
      ;;
    *)
      log "错误: 时间格式无效，请使用 HH:MM，例如 03:00"
      return 1
      ;;
  esac
}

# 检查是否已启用自动更新
is_auto_update_enabled() {
  get_script_path || return 1
  crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH --auto" >/dev/null 2>&1
}

# 重启cron服务以应用配置
restart_cron_service() {
  if [ -x /etc/init.d/cron ]; then
    /etc/init.d/cron restart >/dev/null 2>&1 || {
      log "警告: cron服务重启失败，请手动执行 /etc/init.d/cron restart"
      return 1
    }
  fi
}

# 启用自动更新
enable_auto_update() {
  mkdir -p "$TEMP_DIR"
  CRON_TMP_FILE="${TEMP_DIR}/crontab.tmp"

  get_script_path || {
    log "错误: 无法获取脚本绝对路径"
    return 1
  }

  load_auto_update_schedule >/dev/null 2>&1 || true

  if [ -z "$AUTO_UPDATE_NONINTERACTIVE" ]; then
    prompt_auto_update_time || return 1
  fi

  crontab -l 2>/dev/null | grep -F -v "$SCRIPT_PATH --auto" > "$CRON_TMP_FILE" || true
  get_auto_update_entry >> "$CRON_TMP_FILE" || return 1

  crontab "$CRON_TMP_FILE" || {
    log "错误: 写入自动更新计划任务失败"
    return 1
  }

  restart_cron_service || true
  log "自动更新已启用: $(get_auto_update_time_display)"
  log "脚本路径: ${SCRIPT_PATH}"
  return 0
}

# 禁用自动更新
disable_auto_update() {
  mkdir -p "$TEMP_DIR"
  CRON_TMP_FILE="${TEMP_DIR}/crontab.tmp"

  get_script_path || {
    log "错误: 无法获取脚本绝对路径"
    return 1
  }

  crontab -l 2>/dev/null | grep -F -v "$SCRIPT_PATH --auto" > "$CRON_TMP_FILE" || true

  crontab "$CRON_TMP_FILE" || {
    log "错误: 移除自动更新计划任务失败"
    return 1
  }

  restart_cron_service || true
  log "自动更新已关闭"
  return 0
}

# 尝试从GitHub Release API响应中提取日志
parse_release_json() {
  RELEASE_JSON_FILE="$1"
  PUBLISHED_AT=""
  RELEASE_BODY=""
  RELEASE_TAG=""

  if command -v jsonfilter >/dev/null 2>&1; then
    PUBLISHED_AT=$(jsonfilter -i "$RELEASE_JSON_FILE" -e '@.published_at' 2>/dev/null || echo "")
    RELEASE_BODY=$(jsonfilter -i "$RELEASE_JSON_FILE" -e '@.body' 2>/dev/null || echo "")
    RELEASE_TAG=$(jsonfilter -i "$RELEASE_JSON_FILE" -e '@.tag_name' 2>/dev/null || echo "")
  else
    PUBLISHED_AT=$(sed -n 's/.*"published_at":"\([^"]*\)".*/\1/p' "$RELEASE_JSON_FILE" | head -n 1)
    RELEASE_BODY=$(sed -n 's/.*"body":"\(.*\)","discussion_url".*/\1/p' "$RELEASE_JSON_FILE" | head -n 1)
    RELEASE_TAG=$(sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p' "$RELEASE_JSON_FILE" | head -n 1)

    if [ -n "$RELEASE_BODY" ]; then
      RELEASE_BODY=$(printf '%b' "$(echo "$RELEASE_BODY" | \
        sed 's/\\"/"/g; s/\\\\/\\/g; s/\\r//g; s/\\n/\n/g; s/\\t/\t/g')")
    fi
  fi

  if [ -z "$PUBLISHED_AT" ] && [ -z "$RELEASE_BODY" ]; then
    return 1
  fi

  {
    echo "Changelog"
    [ -n "$PUBLISHED_AT" ] && echo "Published: $PUBLISHED_AT"
    [ -n "$REMOTE_VERSION" ] && echo "Version: $REMOTE_VERSION"
    [ -z "$REMOTE_VERSION" ] && [ -n "$RELEASE_TAG" ] && echo "Release Tag: $RELEASE_TAG"
    echo
    if [ -n "$RELEASE_BODY" ]; then
      echo "$RELEASE_BODY"
    else
      echo "该版本未提供更新说明。"
    fi
  } > "$CHANGELOG_FILE"

  return 0
}

# 确保Nikki核心具有可执行权限
ensure_core_permissions() {
  if [ -f "$CORE_PATH" ] && [ ! -x "$CORE_PATH" ]; then
    log "检测到 ${CORE_PATH} 缺少执行权限，正在修复..."
    chmod 755 "$CORE_PATH" || {
      log "错误: 无法为 ${CORE_PATH} 设置执行权限"
      return 1
    }
  fi
}

# 清理临时文件
clean_temp() {
  # 检查目录是否存在再尝试删除
  if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR" 2>/dev/null || true
  fi
}

# 信号处理
handle_interrupt() {
  echo ""
  echo "用户中断，正在清理..."
  clean_temp
  exit 130
}

# 设置中断信号处理
trap handle_interrupt INT TERM

# 检测系统架构并设置下载URL
detect_arch() {
  ARCH=$(uname -m)
  log "检测到系统架构: $ARCH"
  
  log "使用源代码仓库: $SOURCE_REPO"
  
  # 远程版本信息和兼容性设置
  REMOTE_VERSION=""
  USE_COMPATIBLE=""
  USE_GO_VERSION=""
  
  # 根据架构确定下载文件前缀
  case "$ARCH" in
    "x86_64"|"amd64")
      ARCH_NAME="amd64"
      
      # 检查CPU支持情况
      if ! grep -q "avx" /proc/cpuinfo 2>/dev/null; then
        log "CPU不支持AVX指令集，建议使用兼容版本"
        USE_COMPATIBLE="-compatible"
      fi
      
      # 检查glibc版本
      if [ -x "$(command -v ldd)" ]; then
        GLIBC_VERSION=$(ldd --version | head -n1 | grep -o '[0-9]\+\.[0-9]\+$' || echo "")
        if [ -n "$GLIBC_VERSION" ]; then
          log "系统glibc版本: $GLIBC_VERSION"
          if [ "$(echo "$GLIBC_VERSION < 2.27" | bc 2>/dev/null)" = "1" ]; then
            log "glibc版本低于2.27，建议使用兼容版本"
            USE_COMPATIBLE="-compatible"
          fi
        fi
      fi
      
      # 交互式选择版本变体
      if [ -t 0 ] && [ -z "$AUTO_MODE" ]; then
        echo
        echo "检测到x86_64架构，请选择要下载的版本变体:"
        echo "1. 标准版本 (mihomo-linux-amd64)"
        echo "2. 兼容版本 (mihomo-linux-amd64-compatible)"
        echo "3. Go 1.20版本 (mihomo-linux-amd64-go120)"
        echo "4. Go 1.23版本 (mihomo-linux-amd64-go123)"
        echo "5. 兼容Go 1.20版本 (mihomo-linux-amd64-compatible-go120)"
        echo "6. 兼容Go 1.23版本 (mihomo-linux-amd64-compatible-go123)"
        printf "请输入选项 [1-6] (默认: 1): "
        read -r variant_choice
        
        case "$variant_choice" in
          2) USE_COMPATIBLE="-compatible" ;;
          3) USE_GO_VERSION="-go120" ;;
          4) USE_GO_VERSION="-go123" ;;
          5) USE_COMPATIBLE="-compatible"; USE_GO_VERSION="-go120" ;;
          6) USE_COMPATIBLE="-compatible"; USE_GO_VERSION="-go123" ;;
        esac
      fi
      ;;
    "i386"|"i686"|"x86")
      ARCH_NAME="386"
      
      # 交互式选择版本变体
      if [ -t 0 ] && [ -z "$AUTO_MODE" ]; then
        echo
        echo "检测到x86_32架构，请选择要下载的版本变体:"
        echo "1. 标准版本 (mihomo-linux-386)"
        echo "2. Go 1.20版本 (mihomo-linux-386-go120)"
        echo "3. Go 1.23版本 (mihomo-linux-386-go123)"
        echo "4. Softfloat版本 (mihomo-linux-386-softfloat)"
        printf "请输入选项 [1-4] (默认: 1): "
        read -r variant_choice
        
        case "$variant_choice" in
          2) USE_GO_VERSION="-go120" ;;
          3) USE_GO_VERSION="-go123" ;;
          4) USE_GO_VERSION="-softfloat" ;;
        esac
      fi
      ;;
    "aarch64"|"arm64") ARCH_NAME="arm64" ;;
    "armv7l"|"armv7"|"arm") ARCH_NAME="armv7" ;;
    "mips"|"mipsel") ARCH_NAME="mipsle" ;;
    *)
      log "错误: 不支持的系统架构: $ARCH"
      exit 1
      ;;
  esac
  
  # 构建文件基本名称前缀
  CLASH_BASE_FILENAME="mihomo-${OS}-${ARCH_NAME}${USE_COMPATIBLE:+$USE_COMPATIBLE}${USE_GO_VERSION:+$USE_GO_VERSION}"
  log "文件基础名称: $CLASH_BASE_FILENAME"
  
  # 更新下载基础URL
  BASE_URL="https://github.com/${SOURCE_REPO}/releases/download/${VERSION_TAG}"
  log "下载基础URL: $BASE_URL"
}

# 获取当前内核信息
get_current_info() {
  if [ ! -f "$CORE_PATH" ]; then
    echo "未安装"
    return
  fi

  ensure_core_permissions || return 1
  
  if [ -x "$CORE_PATH" ]; then
    VERSION_FULL=$("$CORE_PATH" -v 2>/dev/null || echo "无法获取版本")
    INSTALL_DATE=$(date -r "$CORE_PATH" "+%Y-%m-%d %H:%M:%S")
    
    # 提取内核版本和系统信息
    CORE_INFO=$(echo "$VERSION_FULL" | head -n 1 | awk '{print $1, $2, $3}')
    SYS_INFO=$(echo "$VERSION_FULL" | head -n 1 | cut -d' ' -f4-)
    
    # 保存完整版本号以供其他函数使用
    LOCAL_VERSION=$(echo "$CORE_INFO" | grep -o 'alpha-[0-9A-Za-z-]*' || echo "")
    
    echo "$CORE_INFO"
    echo "$SYS_INFO"
    echo "安装于: $INSTALL_DATE"
  else
    echo "已安装但无法执行"
  fi
}

# 检查版本并决定是否需要更新
check_version() {
  log "检查版本信息..."
  
  # 确保临时目录存在
  mkdir -p "$TEMP_DIR"
  ensure_core_permissions || return 2
  
  # 获取本地版本号
  if [ -z "$LOCAL_VERSION" ] && [ -f "$CORE_PATH" ] && [ -x "$CORE_PATH" ]; then
    LOCAL_VERSION_FULL=$("$CORE_PATH" -v 2>/dev/null || echo "")
    LOCAL_VERSION=$(echo "$LOCAL_VERSION_FULL" | head -n 1 | grep -o 'alpha-[0-9A-Za-z-]*' || echo "")
  fi
  
  # 获取远程版本号
  TEMP_VERSION="${TEMP_DIR}/version.txt"
  VERSION_URL="https://github.com/${SOURCE_REPO}/releases/download/${VERSION_TAG}/version.txt"
  
  if curl_with_accelerator_fallback "$TEMP_VERSION" -s -L --connect-timeout 10 --max-time 15 "$VERSION_URL"; then
    REMOTE_VERSION=$(cat "$TEMP_VERSION" | tr -d '\r\n')
    
    if [ -n "$REMOTE_VERSION" ] && echo "$REMOTE_VERSION" | grep -q '^alpha-'; then
      # 构建下载URL和文件名
      CLASH_FILENAME="${CLASH_BASE_FILENAME}-${REMOTE_VERSION}.gz"
      CLASH_URL="${BASE_URL}/${CLASH_FILENAME}"
      log "下载URL: $CLASH_URL"
      
      # 检查URL是否有效
      if check_url_available "$CLASH_URL"; then
        log "URL验证成功"
      else
        log "警告: URL验证失败，但仍将尝试下载"
      fi
      
      # 显示版本信息
      echo "远程版本: $REMOTE_VERSION"
      echo "本地版本: ${LOCAL_VERSION:-未知}"
      
      # 比较版本
      if [ -z "$LOCAL_VERSION" ] || [ "$LOCAL_VERSION" != "$REMOTE_VERSION" ]; then
        HAS_UPDATE="true"
        return 0  # 有更新可用
      else
        HAS_UPDATE="false"
        return 1  # 无需更新
      fi
    else
      log "无法提取远程版本号，版本文件内容异常"
      return 2  # 提取失败
    fi
  else
    log "无法访问版本信息，请检查网络连接"
    return 2  # 访问失败
  fi
}

# 下载并更新内核
update_core() {
  # 确保已获取版本信息
  if [ -z "$CLASH_FILENAME" ] || [ -z "$CLASH_URL" ]; then
    check_version
    ret_val=$?
    
    if [ $ret_val -eq 1 ]; then
      log "当前已是最新版本，无需更新"
      return 0
    elif [ $ret_val -eq 2 ]; then
      log "错误: 无法获取版本信息"
      return 1
    fi
  fi
  
  # 确保临时目录存在
  mkdir -p "$TEMP_DIR"
  mkdir -p "$CORE_DIR"
  
  # 下载内核文件
  echo "下载内核中..."
  if download_file "$CLASH_URL" "${TEMP_DIR}/${CLASH_FILENAME}"; then
    echo "完成"
  else
    echo "失败"
    log "错误: 无法下载内核文件，请检查网络连接"
    return 1
  fi
  
  # 解压文件
  echo -ne "解压内核文件..."
  if gzip -d -c "${TEMP_DIR}/${CLASH_FILENAME}" > "${TEMP_DIR}/mihomo" &&
     chmod 755 "${TEMP_DIR}/mihomo"; then
    echo "完成"
  else
    echo "失败"
    log "错误: 解压文件或设置 mihomo 权限失败"
    return 1
  fi
  
  # 备份旧内核文件
  if [ -f "$CORE_PATH" ]; then
    echo -ne "备份现有内核文件..."
    cp "$CORE_PATH" "$CORE_BACKUP_PATH"
    echo "完成"
  fi
  
  # 移动新内核文件
  echo -ne "安装新内核..."
  if cp "${TEMP_DIR}/mihomo" "$CORE_PATH"; then
    chmod 755 "$CORE_PATH"
    echo "完成"
  else
    echo "失败"
    log "错误: 无法复制新内核文件"
    return 1
  fi
  
  # 重启Nikki服务
  echo -ne "重启Nikki服务..."
  if "$SERVICE_SCRIPT" restart >/dev/null 2>&1; then
    echo "完成"
  else
    echo "失败"
    log "错误: 重启Nikki服务失败"
    return 1
  fi
  
  echo -e "${GREEN}Nikki Mihomo Smart内核更新成功完成！${NC}"
  return 0
}

# 回滚到备份版本
rollback() {
  if [ ! -f "$CORE_BACKUP_PATH" ]; then
    log "错误: 没有找到备份文件"
    return 1
  fi
  
  log "开始回滚到备份版本..."
  
  # 备份当前版本
  if [ -f "$CORE_PATH" ]; then
    cp "$CORE_PATH" "$CORE_CURRENT_PATH"
    log "当前版本已备份为 $(basename "$CORE_CURRENT_PATH")"
  fi
  
  # 恢复备份
  cp "$CORE_BACKUP_PATH" "$CORE_PATH" && chmod 755 "$CORE_PATH" || {
    log "错误: 无法恢复备份文件"
    return 1
  }
  
  # 重启Nikki服务
  log "重启Nikki服务..."
  "$SERVICE_SCRIPT" restart || {
    log "错误: 重启Nikki服务失败"
    return 1
  }
  
  log "成功回滚到备份版本！"
  return 0
}

# 获取最新的更新日志
get_latest_changelog() {
  log "获取最新更新日志..."
  
  # 确保临时目录存在
  mkdir -p "$TEMP_DIR"
  RELEASE_API_URL="https://api.github.com/repos/${SOURCE_REPO}/releases/tags/${VERSION_TAG}"
  RELEASE_JSON_FILE="${TEMP_DIR}/release.json"
  RELEASE_PAGE_FILE="${TEMP_DIR}/release_page.html"

  # 优先通过GitHub Release API获取日志
  if curl_with_accelerator_fallback "$RELEASE_JSON_FILE" -s -L --connect-timeout 10 --max-time 20 \
    -H "Accept: application/vnd.github+json" \
    "$RELEASE_API_URL"; then
    if parse_release_json "$RELEASE_JSON_FILE"; then
      return 0
    fi
    log "API日志解析失败，尝试回退到网页提取..."
  else
    log "无法访问GitHub Release API，尝试回退到网页提取..."
  fi

  # 回退到旧的网页提取方式
  if curl_with_accelerator_fallback "$RELEASE_PAGE_FILE" -s -L --connect-timeout 10 --max-time 20 "https://github.com/${SOURCE_REPO}/releases/tag/${VERSION_TAG}"; then
    echo "Changelog" > "$CHANGELOG_FILE"

    if command -v lynx >/dev/null 2>&1; then
      lynx -dump -nolist "$RELEASE_PAGE_FILE" > "${TEMP_DIR}/page_text.txt"
    elif command -v w3m >/dev/null 2>&1; then
      w3m -dump "$RELEASE_PAGE_FILE" > "${TEMP_DIR}/page_text.txt"
    else
      sed 's/<[^>]*>//g; s/&nbsp;/ /g; s/&lt;/</g; s/&gt;/>/g; s/&#39;/'"'"'/g' "$RELEASE_PAGE_FILE" > "${TEMP_DIR}/page_text.txt"
    fi

    DATE_LINES=$(grep -n "Date: " "${TEMP_DIR}/page_text.txt" | cut -d: -f1)
    FIRST_DATE_LINE=$(echo "$DATE_LINES" | head -n 1)
    SECOND_DATE_LINE=$(echo "$DATE_LINES" | head -n 2 | tail -n 1)

    if [ -n "$FIRST_DATE_LINE" ]; then
      if [ -n "$SECOND_DATE_LINE" ]; then
        sed -n "${FIRST_DATE_LINE},$(($SECOND_DATE_LINE - 1))p" "${TEMP_DIR}/page_text.txt" >> "$CHANGELOG_FILE"
      else
        sed -n "${FIRST_DATE_LINE},\$p" "${TEMP_DIR}/page_text.txt" >> "$CHANGELOG_FILE"
      fi

      if grep -q "Date: " "$CHANGELOG_FILE"; then
        return 0
      fi
    fi

    log "无法提取Changelog内容"
    return 1
  fi

  log "无法获取发布页面，请检查网络连接"
  return 1
}

# 显示最新的更新日志
show_changelog() {
  clear
  echo "==========================================="
  echo "      Nikki Mihomo Smart 最新更新日志     "
  echo "==========================================="
  echo
  
  # 重定向日志到/dev/null，不显示在屏幕上
  if [ ! -f "$CHANGELOG_FILE" ] || [ ! -s "$CHANGELOG_FILE" ]; then
    { get_latest_changelog; } > /dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo -e "${RED}无法获取更新日志，提取失效${NC}"
      echo -e "请前往 https://github.com/${SOURCE_REPO}/releases/tag/${VERSION_TAG} 查看"
      echo
      read -p "按回车键返回主菜单..." dummy
      return
    fi
  fi
  
  # 优化显示，优先完整显示API日志，网页回退模式下继续过滤噪音
  sed '/^$/N;/^\n$/D' "$CHANGELOG_FILE" | grep -v "Assets" | grep -v "Loading" | grep -v "Uh oh!" | grep -v "There was an error" > "${TEMP_DIR}/clean_log.txt"
  cat "${TEMP_DIR}/clean_log.txt"
  echo
  echo "==========================================="
  read -p "按回车键返回主菜单..." dummy
}

# 自动更新设置菜单
manage_auto_update() {
  clear
  echo "==========================================="
  echo "        Nikki 自动更新设置"
  echo "==========================================="
  echo

  load_auto_update_schedule >/dev/null 2>&1 || true

  if is_auto_update_enabled; then
    AUTO_UPDATE_STATUS="${GREEN}已启用${NC}"
  else
    AUTO_UPDATE_STATUS="${YELLOW}未启用${NC}"
  fi

  get_script_path >/dev/null 2>&1 || true
  echo -e "当前状态: ${AUTO_UPDATE_STATUS}"
  echo "执行时间: 每天 $(get_auto_update_time_display)"
  echo "脚本路径: ${SCRIPT_PATH:-未知}"
  echo "日志路径: ${AUTO_UPDATE_LOG}"
  echo
  echo "1. 启用或更新时间自动更新任务"
  echo "2. 关闭自动更新任务"
  echo "0. 返回主菜单"
  echo "==========================================="

  printf "请输入选项 [0-2]: "
  read -r auto_choice

  case $auto_choice in
    1)
      enable_auto_update
      ;;
    2)
      disable_auto_update
      ;;
    0)
      return 0
      ;;
    *)
      echo "无效的选择，请重试"
      ;;
  esac

  echo
  read -p "按回车键返回主菜单..." dummy
}

# 显示菜单
show_menu() {
  clear
  load_auto_update_schedule >/dev/null 2>&1 || true
  
  echo "==========================================="
  echo "   Nikki Mihomo Smart 内核管理脚本 v${SCRIPT_VERSION}   "
  echo "==========================================="
  echo "当前内核: "
  get_current_info
  echo
  
  # 显示更新提示（如果有）
  if [ "$HAS_UPDATE" = "true" ]; then
    echo -e "${RED}发现新版本: $REMOTE_VERSION !${NC}"
  elif [ -n "$REMOTE_VERSION" ]; then
    echo -e "${GREEN}当前已是最新版本: $LOCAL_VERSION${NC}"
  fi
  echo
  
  # 添加说明区域
  echo -e "说明: "
  echo -e "- 本工具用于管理Nikki的Mihomo Smart内核"
  echo -e "- Nikki默认核心路径: ${CORE_PATH}"
  echo -e "- 更新前会自动备份当前内核"
  echo -e "- 如更新后出现问题，可使用回滚功能还原"
  echo -e "- 下载直连失败会自动尝试GitHub加速: ${GITHUB_ACCELERATOR}"
  if is_auto_update_enabled; then
    echo -e "- 自动更新状态: ${GREEN}已启用${NC} (每天 $(get_auto_update_time_display))"
  else
    echo -e "- 自动更新状态: ${YELLOW}未启用${NC}"
  fi
  echo -e "- 也可以使用: ./smartcore.sh -c 仅查看更新日志"
  echo
  
  echo "请选择操作:"
  echo "1. 检查并更新内核"
  echo "2. 仅检查更新"
  echo "3. 回滚到上一版本"
  echo "4. 查看最新更新日志"
  echo "5. 设置自动更新"
  echo "0. 退出"
  echo "==========================================="
  
  printf "请输入选项 [0-5]: "
  read -r choice
  
  case $choice in
    1)
      detect_arch
      check_version
      if [ "$HAS_UPDATE" = "true" ]; then
        echo -e "${GREEN}发现新版本！准备更新内核...${NC}"
        update_core
      else
        echo -e "${GREEN}当前已是最新版本，无需更新${NC}"
      fi
      echo
      read -p "按回车键继续..." dummy
      ;;
    2)
      detect_arch
      if check_version; then
        echo -e "${GREEN}发现新版本！${NC}"
        echo -n "是否立即更新？[y/N]: "
        read -r update_now
        if [ "$update_now" = "y" ] || [ "$update_now" = "Y" ]; then
          update_core
        fi
      else
        echo -e "${GREEN}当前已是最新版本，无需更新${NC}"
      fi
      echo
      read -p "按回车键继续..." dummy
      ;;
    3)
      rollback
      echo
      read -p "按回车键继续..." dummy
      ;;
    4)
      show_changelog
      ;;
    5)
      manage_auto_update
      ;;
    0)
      echo "感谢使用！"
      # 提前清理临时文件，避免EXIT陷阱重复调用时出错
      clean_temp
      # 使用trap '' EXIT来移除之前的EXIT陷阱
      trap '' EXIT
      exit 0
      ;;
    *)
      echo "无效的选择，请重试"
      sleep 2
      ;;
  esac
}

# 自动更新模式
auto_update() {
  log "开始自动更新检查..."
  detect_arch
  
  if check_version; then
    log "检测到新版本，开始更新..."
    # 获取并显示更新日志
    if get_latest_changelog; then
      echo "==========================================="
      echo "      新版本更新日志     "
      echo "==========================================="
      cat "$CHANGELOG_FILE"
      echo "==========================================="
    else
      echo "==========================================="
      echo "      无法获取更新日志，提取失效     "
      echo "==========================================="
    fi
    update_core
    clean_temp
    return 0
  else
    log "当前已是最新版本，无需更新"
    clean_temp
    return 1
  fi
}

# 主函数
main() {
  # 创建临时目录
  mkdir -p "$TEMP_DIR"
  
  # 注册退出清理
  trap clean_temp EXIT
  
  # 检查命令行参数
  if [ "$1" = "--auto" ] || [ "$1" = "-a" ]; then
    AUTO_MODE="1"
    auto_update
    exit $?
  elif [ "$1" = "--debug" ] || [ "$1" = "-d" ]; then
    DEBUG_MODE="1"
    log "开启调试模式"
  elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Nikki Mihomo Smart 内核管理脚本 v${SCRIPT_VERSION}"
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -a, --auto    自动检查并更新内核"
    echo "  -d, --debug   显示调试信息"
    echo "  -h, --help    显示此帮助信息"
    echo "  -c, --changelog  仅显示最新更新日志"
    echo "  无参数        显示交互式菜单"
    exit 0
  elif [ "$1" = "--changelog" ] || [ "$1" = "-c" ]; then
    get_latest_changelog && cat "$CHANGELOG_FILE" || echo -e "${RED}无法获取更新日志，提取失效${NC}"
    exit $?
  fi
  
  # 如果没有提供参数，进入交互式模式
  if [ -z "$1" ]; then
    # 设置为交互式模式
    INTERACTIVE_MODE="1"
    log "进入交互式模式，直接显示主菜单"
    
    # 循环显示交互式菜单，无需先检测版本
    while true; do
      show_menu
    done
  else
    # 非交互式模式下直接更新
    AUTO_MODE="1"
    auto_update
  fi
}

# 运行主程序
main "$@" 
