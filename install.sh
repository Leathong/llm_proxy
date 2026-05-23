#!/bin/bash
#
# 一键编译安装 LLMProxy
# 如果已安装则覆盖，未安装则安装到 /Applications
#

set -e

APP_NAME="LLMProxy"
BUILD_DIR="build/macos/Build/Products/Release"
DEST_DIR="/Applications"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 切换到项目根目录
cd "$(dirname "$0")"

info "开始编译 $APP_NAME ..."

# 1. 获取依赖
# if ! flutter pub get; then
#     error "flutter pub get 失败"
#     exit 1
# fi

# 2. 编译 macOS release 版本
if ! flutter build macos --release; then
    error "编译失败"
    exit 1
fi

info "编译成功"

# 3. 检查产物
APP_PATH="$BUILD_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    error "未找到编译产物: $APP_PATH"
    exit 1
fi

# 4. 如果已安装，先移除旧版本
INSTALLED_PATH="$DEST_DIR/$APP_NAME.app"
if [ -d "$INSTALLED_PATH" ]; then
    warn "检测到已安装版本，正在移除 ..."
    rm -rf "$INSTALLED_PATH"
fi

# 5. 复制到 /Applications
info "正在安装到 $DEST_DIR ..."
cp -R "$APP_PATH" "$DEST_DIR/"
info "安装完成！"

# 6. 打开应用
info "启动 $APP_NAME ..."
open "$INSTALLED_PATH"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  $APP_NAME 已安装并启动成功！${NC}"
echo -e "${GREEN}========================================${NC}"
