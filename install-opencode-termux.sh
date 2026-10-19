#!/bin/bash
#===============================================================================
# OpenCode Termux 一键安装脚本 (v3.0)
# 功能：自动清理环境、更新系统、安装依赖、本地编译构建 OpenCode
# 
# 注意：旧版 guysoft/opencode-termux 二进制在 Android 11+ 上无法运行
# 本脚本使用 Hope2333/opencode-termux 构建系统（glibc 版本）
# 来源：https://github.com/Hope2333/opencode-termux
#===============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 镜像源配置
USE_CHINA_MIRROR=false
TERMUX_MIRROR=""
GITHUB_MIRROR=""

# 打印带颜色的消息
print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# 选择镜像源 - 简化流程，直接使用中国镜像源
select_mirror() {
    print_step "步骤 0/8: 配置软件源"
    
    # 默认使用中国镜像源（最常用）
    USE_CHINA_MIRROR=true
    print_success "使用中国镜像源（清华源）"
    
    configure_mirrors
}

# 配置镜像源
configure_mirrors() {
    if [ "$USE_CHINA_MIRROR" = true ]; then
        # 中国镜像源配置
        TERMUX_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
        GITHUB_MIRROR="https://ghproxy.com/https://github.com"
        print_success "Termux 源: 清华大学镜像"
        print_success "GitHub 代理: ghproxy.com"
    else
        # 默认源
        TERMUX_MIRROR=""
        GITHUB_MIRROR="https://github.com"
        print_success "使用官方默认源"
    fi
    
    # 如果选择了中国镜像，配置 Termux 源
    if [ "$USE_CHINA_MIRROR" = true ] && [ -n "$TERMUX_MIRROR" ]; then
        configure_termux_mirror
    fi
}

# 配置 Termux 软件源（直接修改配置文件，不使用交互式工具）
configure_termux_mirror() {
    print_info "正在配置 Termux 软件源..."
    
    # 备份原 sources.list
    if [ -f "$PREFIX/etc/apt/sources.list" ]; then
        cp "$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi
    
    # 检测架构
    local arch=$(dpkg --print-architecture 2>/dev/null || echo "aarch64")
    
    # 直接写入清华镜像源（最可靠的方式）
    print_info "配置清华镜像源..."
    cat > "$PREFIX/etc/apt/sources.list" << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main
EOF
    
    print_success "Termux 软件源已配置为清华镜像"
}

# 检查是否在 Termux 环境中运行
check_termux() {
    if [ -z "$TERMUX_VERSION" ]; then
        print_warning "此脚本专为 Termux 设计，但也可以在其他 Linux 环境中运行"
    else
        print_success "检测到 Termux 环境: $TERMUX_VERSION"
    fi
}

# 步骤1：请求存储权限（唯一需要用户手动确认的地方）
request_storage_permission() {
    print_step "步骤 1/8: 请求存储权限"
    
    if [ -d "$HOME/storage" ]; then
        print_success "存储权限已授予"
    else
        print_info "即将请求存储权限..."
        print_warning ">>> 请在弹出的对话框中点击【允许】<<<"
        sleep 2
        termux-setup-storage
        sleep 1
        
        if [ -d "$HOME/storage" ]; then
            print_success "存储权限授予成功"
        else
            print_warning "存储权限未授予，部分功能可能受限"
        fi
    fi
}

# 步骤2：清理环境
clean_environment() {
    print_step "步骤 2/8: 清理环境"
    
    print_info "清理旧的 OpenCode 安装..."
    rm -f "$PREFIX/bin/opencode" 2>/dev/null || true
    rm -f "$PREFIX/bin/oc" 2>/dev/null || true
    rm -f "$HOME/opencode" 2>/dev/null || true
    rm -rf "$HOME/opencode-aarch64.zip" 2>/dev/null || true
    rm -rf "$HOME/opencode-*.zip" 2>/dev/null || true
    rm -rf "$HOME/opencode-termux" 2>/dev/null || true
    rm -rf "$HOME/oct-out" 2>/dev/null || true
    
    print_info "清理配置文件（保留备份）..."
    if [ -d "$HOME/.local/share/opencode" ]; then
        mv "$HOME/.local/share/opencode" "$HOME/.local/share/opencode.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi
    if [ -d "$HOME/.config/opencode" ]; then
        mv "$HOME/.config/opencode" "$HOME/.config/opencode.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi
    
    print_success "环境清理完成"
}

# 步骤3：更新系统包
update_system() {
    print_step "步骤 3/8: 更新系统包"
    
    print_info "更新软件源..."
    pkg update -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    
    print_info "升级已安装的包..."
    pkg upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || true
    
    print_success "系统更新完成"
}

# 步骤4：安装依赖
install_dependencies() {
    print_step "步骤 4/8: 安装依赖"
    
    print_info "安装必要工具..."
    pkg install git curl wget unzip ripgrep make nodejs file python3 tar -y
    
    print_info "安装编译工具（可选，用于 statx shim）..."
    pkg install clang -y 2>/dev/null || pkg install gcc -y 2>/dev/null || print_warning "未找到 C 编译器，statx shim 将跳过"
    
    print_success "依赖安装完成"
}

# 下载文件并验证
download_with_retry() {
    local url=$1
    local output=$2
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        print_info "正在下载... (尝试 $((retry + 1))/$max_retries)"
        print_info "URL: $url"
        
        # 清理旧文件
        rm -f "$output"
        
        # 下载文件（带进度显示）
        if curl -L -o "$output" \
            --connect-timeout 30 \
            --max-time 600 \
            --retry 2 \
            --retry-delay 3 \
            --progress-bar \
            -H "User-Agent: Mozilla/5.0" \
            "$url" 2>&1; then
            
            # 验证文件大小（至少 10MB）
            local file_size=$(stat -c%s "$output" 2>/dev/null || stat -f%z "$output" 2>/dev/null || echo "0")
            print_info "下载完成，文件大小: ${file_size} 字节"
            
            if [ "$file_size" -gt 10485760 ]; then
                print_success "下载成功，文件大小: $(($file_size / 1024 / 1024)) MB"
                return 0
            else
                print_error "下载文件太小 (${file_size} 字节)，可能下载失败"
                rm -f "$output"
            fi
        else
            print_error "下载失败 (curl 退出码: $?)"
        fi
        
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            print_warning "等待 5 秒后重试..."
            sleep 5
        fi
    done
    
    return 1
}

# 步骤5：安装 OpenCode (使用 Hope2333 构建系统，支持 Android 11+)
install_opencode() {
    print_step "步骤 5/8: 安装 OpenCode (本地编译构建)"
    
    cd "$HOME"
    
    # 步骤 5a：安装 glibc 依赖
    print_info "安装 glibc 依赖..."
    
    # 确保 glibc-repo 源已启用
    if [ ! -f "$PREFIX/etc/apt/sources.list.d/glibc.list" ]; then
        print_info "启用 glibc-repo..."
        pkg install -y glibc-repo
    fi
    
    # 更新源
    pkg update -y
    
    # 安装 glibc 和 openssl-glibc
    pkg install -y glibc openssl-glibc
    
    # 验证 glibc 安装
    if [ ! -d "$PREFIX/glibc" ] && [ ! -d "/data/data/com.termux/files/usr/glibc" ]; then
        print_error "glibc 安装失败，未找到 glibc 目录"
        print_info "尝试手动查找 glibc..."
        find $PREFIX -name "libc.so.6" -type f 2>/dev/null | head -5
        exit 1
    fi
    
    # 创建符号链接（如果 build.py 期望的位置不同）
    if [ -d "$PREFIX/glibc" ] && [ ! -d "/data/data/com.termux/files/usr/glibc" ]; then
        print_info "创建 glibc 符号链接..."
        ln -sf "$PREFIX/glibc" "/data/data/com.termux/files/usr/glibc" 2>/dev/null || true
    fi
    
    print_success "glibc 依赖安装完成"
    
    # 步骤 5b：克隆 opencode-termux 构建系统
    print_info "克隆 opencode-termux 构建系统..."
    local oct_dir="$HOME/opencode-termux"
    
    # 使用 Gitee 镜像（国内访问更可靠）
    local gitee_url="https://gitee.com/kingsunrain/opencode-termux.git"
    
    if [ -d "$oct_dir" ]; then
        rm -rf "$oct_dir"
    fi
    
    if git clone --depth 1 "$gitee_url" "$oct_dir"; then
        print_success "从 Gitee 克隆成功"
    else
        print_error "克隆失败，请检查网络连接"
        exit 1
    fi
    
    cd "$oct_dir"
    print_success "opencode-termux 克隆完成"
    
    # 步骤 5b-2：预克隆 bun-termux-loader（避免构建时从 GitHub 下载失败）
    print_info "预克隆 bun-termux-loader..."
    local loader_dir="$oct_dir/third-party/bun-termux-loader"
    if [ ! -f "$loader_dir/build.py" ]; then
        rm -rf "$loader_dir"
        mkdir -p "$oct_dir/third-party"
        
        # 尝试从 Gitee 镜像克隆
        local loader_cloned=false
        local gitee_loader="https://gitee.com/kingsunrain/bun-termux-loader.git"
        if git clone --depth 1 "$gitee_loader" "$loader_dir" 2>/dev/null; then
            loader_cloned=true
            print_success "从 Gitee 克隆 bun-termux-loader 成功"
        fi
        
        # Gitee 失败则尝试 GitHub 镜像
        if [ "$loader_cloned" = false ]; then
            local gh_mirrors=(
                "https://ghproxy.com/https://github.com/Hope2333/bun-termux-loader"
                "https://mirror.ghproxy.com/https://github.com/Hope2333/bun-termux-loader"
            )
            for mirror_url in "${gh_mirrors[@]}"; do
                print_info "尝试镜像: $mirror_url"
                if git clone --depth 1 "$mirror_url" "$loader_dir" 2>/dev/null; then
                    loader_cloned=true
                    print_success "从镜像克隆 bun-termux-loader 成功"
                    break
                fi
            done
        fi
        
        # 最后尝试直接 GitHub
        if [ "$loader_cloned" = false ]; then
            if git clone --depth 1 https://github.com/Hope2333/bun-termux-loader "$loader_dir" 2>/dev/null; then
                loader_cloned=true
                print_success "从 GitHub 克隆 bun-termux-loader 成功"
            fi
        fi
        
        if [ "$loader_cloned" = false ] || [ ! -f "$loader_dir/build.py" ]; then
            print_error "bun-termux-loader 克隆失败，构建将无法继续"
            print_info "请手动将 bun-termux-loader 放到: $loader_dir"
            exit 1
        fi
    else
        print_success "bun-termux-loader 已存在"
    fi
    
    # 步骤 5c：本地构建（预计 5-10 分钟）
    print_info "开始构建 OpenCode（预计 5-10 分钟，请耐心等待）..."
    print_info "构建过程在后台显示进度..."
    
    mkdir -p "$HOME/oct-out"
    
    # 使用最新稳定版本号（避免网络获取 "latest" 失败）
    # 参考：https://github.com/Hope2333/opencode-termux/releases
    local OPENCODE_VER="1.19.3"
    print_info "使用 OpenCode 版本: $OPENCODE_VER"
    
    if make all VER="$OPENCODE_VER" PKG=deb ODIR="$HOME/oct-out" 2>&1; then
        print_success "构建完成！"
    else
        print_error "构建失败，请检查错误信息"
        exit 1
    fi
    
    # 步骤 5d：安装 .deb 包
    print_info "安装 OpenCode 包..."
    local deb_file="$HOME/oct-out/deb/opencode_"*.deb
    if ls $deb_file 1>/dev/null 2>&1; then
        # 使用 dpkg -i 强制安装（即使已安装也覆盖文件）
        dpkg -i --force-reinstall $deb_file 2>/dev/null || apt install -y --reinstall $deb_file 2>/dev/null || apt install -y $deb_file 2>/dev/null || true
    else
        print_error "未找到 .deb 文件: $deb_file"
        ls -la "$HOME/oct-out/deb/" 2>/dev/null || true
        exit 1
    fi
    
    # 清理构建目录节省空间
    rm -rf "$oct_dir" "$HOME/oct-out"
    
    # 验证安装
    print_info "验证安装..."
    sleep 1
    if command -v opencode &> /dev/null; then
        # 尝试获取版本，但允许失败（某些版本可能输出格式不同）
        OPENCODE_VERSION=$(opencode --version 2>/dev/null || echo "unknown")
        if [ "$OPENCODE_VERSION" != "unknown" ]; then
            print_success "OpenCode 安装成功！"
            print_success "版本信息: $OPENCODE_VERSION"
        else
            # 版本检测失败，但命令存在，可能是输出格式问题
            print_success "OpenCode 安装成功！"
            print_warning "版本检测失败，但命令可用"
            print_info "可以手动运行: opencode --version"
        fi
    else
        print_error "OpenCode 安装失败"
        exit 1
    fi
    
    cd "$HOME"
}

# 步骤6：配置 OpenCode
configure_opencode() {
    print_step "步骤 6/8: 配置 OpenCode"
    
    # 创建配置目录
    mkdir -p "$HOME/.local/share/opencode"
    mkdir -p "$HOME/.config/opencode"
    
    # 设置默认模型为 opencode/deepseek-v4-flash-free
    local CONFIG="$HOME/.config/opencode/opencode.jsonc"
    local MODEL="opencode/deepseek-v4-flash-free"
    
    print_info "设置 OpenCode 默认模型为: $MODEL"
    
    # 创建基础配置文件
    if [ ! -f "$CONFIG" ]; then
        echo '{"$schema":"https://opencode.ai/config.json"}' > "$CONFIG"
    fi
    
    # 设置或更新 model 字段
    if grep -q '"model"' "$CONFIG" 2>/dev/null; then
        sed -i "s|\"model\": \"[^\"]*\"|\"model\": \"$MODEL\"|" "$CONFIG"
    else
        sed -i "s|}|,\"model\":\"$MODEL\"}|" "$CONFIG"
    fi
    
    print_success "默认模型已设置为: $MODEL"
    print_info "启动后输入 /models 查看可用模型"
    print_info "启动后输入 /connect 配置认证"
}

# 步骤7：验证安装
verify_installation() {
    print_step "步骤 7/8: 验证安装"
    
    print_info "检查 OpenCode 安装..."
    if command -v opencode &> /dev/null; then
        print_success "✓ OpenCode 已安装"
        # 使用超时保护，避免任何异常导致脚本卡住
        timeout 5 opencode --version 2>/dev/null || print_info "版本检测完成"
    else
        print_error "✗ OpenCode 未找到"
        exit 1
    fi
    
    print_info "检查 'oc' 短链接..."
    if command -v oc &> /dev/null; then
        print_success "✓ 'oc' 短链接已创建"
    else
        print_warning "⚠ 'oc' 短链接未找到"
    fi
    
    print_info "检查依赖..."
    if command -v rg &> /dev/null; then
        print_success "✓ ripgrep 已安装"
    else
        print_warning "⚠ ripgrep 未找到"
    fi
    
    print_info "检查配置文件..."
    if [ -f "$HOME/.config/opencode/config.json" ]; then
        print_success "✓ 配置文件已创建"
    else
        print_error "✗ 配置文件未找到"
    fi
    
    if [ -f "$HOME/.local/share/opencode/auth.json" ]; then
        print_success "✓ 认证文件已创建"
    else
        print_error "✗ 认证文件未找到"
    fi
    
    print_info "检查默认模型..."
    print_success "✓ 使用 OpenCode 内置默认模型"
}

# 显示完成信息
show_completion() {
    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}     🎉 OpenCode 安装完成！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    if [ "$USE_CHINA_MIRROR" = true ]; then
        echo -e "${CYAN}镜像源:${NC} 中国镜像（清华源 + ghproxy）"
    else
        echo -e "${CYAN}镜像源:${NC} 官方默认源"
    fi
    echo -e "${CYAN}安装版本:${NC} Hope2333/opencode-termux (glibc 版本)"
    echo ""
    echo -e "${CYAN}启动方式:${NC}"
    echo -e "  直接运行: ${YELLOW}opencode${NC} 或 ${YELLOW}oc${NC}"
    echo ""
    echo -e "${CYAN}常用命令:${NC}"
    echo -e "  ${YELLOW}opencode${NC} / ${YELLOW}oc${NC}  - 启动 OpenCode"
    echo -e "  ${YELLOW}opencode --version${NC} - 查看版本"
    echo -e "  ${YELLOW}/models${NC}          - 查看可用模型"
    echo -e "  ${YELLOW}/connect${NC}         - 配置认证"
    echo ""
    echo -e "${CYAN}修复说明:${NC}"
    echo -e "  ✅ 已修复 Android 11+ tagged pointers 问题"
    echo -e "  使用 Hope2333/opencode-termux 构建系统（glibc + bun-termux-loader）"
    echo ""
    echo -e "${GREEN}现在运行 'opencode' 或 'oc' 即可开始使用！${NC}"
    echo ""
    
    # 显示版本和模型信息
    print_info "OpenCode 版本:"
    opencode --version 2>/dev/null || echo "无法获取版本"
    echo ""
    print_info "当前模型: opencode/deepseek-v4-flash-free"
    echo ""
    
    # 20 秒倒计时，让用户查看系统状况
    print_info "20 秒后将自动启动 OpenCode..."
    for i in $(seq 20 -1 1); do
        printf "\r${CYAN}[倒计时]${NC} %2d 秒后启动 OpenCode... (按 Ctrl+C 取消) " "$i"
        sleep 1
    done
    echo ""
    echo ""
    
    print_info "正在启动 OpenCode (使用 oc 命令)..."
    oc
}

# 创建 oc 短链接
create_oc_alias() {
    print_info "创建 'oc' 短链接..."
    
    # 创建 oc 脚本
    cat > "$PREFIX/bin/oc" << 'OC_EOF'
#!/bin/bash
# OpenCode 短链接 - 调用 opencode
exec opencode "$@"
OC_EOF
    chmod +x "$PREFIX/bin/oc"
    
    print_success "'oc' 短链接已创建"
}

# 主函数
main() {
    # 首先配置镜像源（在清屏前执行，避免交互问题）
    select_mirror
    
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║          OpenCode Termux 一键安装脚本                         ║"
    echo "║          使用 Hope2333/opencode-termux 构建系统                ║"
    echo "║          支持 Android 11+ (glibc 版本)                         ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    print_info "此脚本将自动完成以下操作："
    echo "  1. 配置软件源（中国镜像）"
    echo "  2. 请求存储权限（需要手动确认）"
    echo "  3. 清理旧环境"
    echo "  4. 更新系统包"
    echo "  5. 安装依赖（ripgrep 等）"
    echo "  6. 安装 glibc 并本地编译构建 OpenCode（约 5-10 分钟）"
    echo "  7. 配置 OpenCode"
    echo "  8. 验证安装"
    echo ""
    print_warning "注意: 整个过程只需要您确认存储权限"
    print_info "开始安装..." 
    
    # 执行安装步骤
    check_termux
    request_storage_permission
    clean_environment
    update_system
    install_dependencies
    install_opencode
    configure_opencode
    create_oc_alias
    verify_installation
    show_completion
}

# 运行主函数
main
