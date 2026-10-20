#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
# OpenCode V2 一键安装脚本（Termux / arm64）
#
# 用法:
#   bash install-opencode-v2.sh
#
# 说明:
#   - 默认使用国内镜像（Termux 主源 TUNA，npm 使用 npmmirror）
#   - 只安装/更新，不提供卸载
#   - 可重复运行，用于安装或更新到最新版
# ==============================================================================

set -Eeuo pipefail

# 兼容 curl ... | bash：避免 pkg/apt 读取 stdin 吃掉脚本后续内容
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

if [ "$#" -ne 0 ]; then
  echo "参数非法，已忽略，开始安装"
fi

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"

NPM_MIRROR="https://registry.npmmirror.com"
NPM_OFFICIAL="https://registry.npmjs.org"
APT_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main"
APT_OFFICIAL="https://packages-cf.termux.dev/apt/termux-main"

SOURCES="$PREFIX/etc/apt/sources.list"
SOURCES_BAK="$PREFIX/etc/apt/sources.list.opencode-v2.bak"

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''
fi

info() { printf '%s[信息]%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()   { printf '%s[完成]%s %s\n' "$C_OK"   "$C_RESET" "$*"; }
warn() { printf '%s[注意]%s %s\n' "$C_WARN" "$C_RESET" "$*"; }
die()  { printf '%s[失败]%s %s\n' "$C_ERR"  "$C_RESET" "$*" >&2; exit 1; }

trap 'die "安装失败（第 $LINENO 行），请检查上方日志"' ERR

# ---------------------------------------------------------------- 存储权限
# 脚本本身不依赖 /sdcard；已授权则跳过，拒绝也静默继续
if ! ls "$HOME_DIR/storage/downloads" >/dev/null 2>&1; then
  if command -v termux-setup-storage >/dev/null 2>&1; then
    info "正在打开系统存储权限..."
    termux-setup-storage >/dev/null 2>&1 </dev/null || true
  fi
fi

# ---------------------------------------------------------------- 环境检查
info "检查运行环境..."
command -v pkg >/dev/null 2>&1 || die "未找到 pkg，请在 Termux 中运行"

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) ;;
  *) die "仅支持 arm64，当前架构: $ARCH" ;;
esac

AVAIL_KB="$(df -Pk "$HOME_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
if [ -n "$AVAIL_KB" ] && [ "$AVAIL_KB" -lt 500000 ]; then
  die "磁盘剩余空间不足 500 MB（当前约 $((AVAIL_KB / 1024)) MB）"
fi
ok "环境检查通过（$ARCH）"

# ---------------------------------------------------------------- 切换国内源
switch_to_tuna() {
  if grep -qs "mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main" "$SOURCES"; then
    info "apt 主源已经是 TUNA"
    return 0
  fi
  mkdir -p "$PREFIX/etc/apt"
  if [ -f "$SOURCES" ] && [ ! -f "$SOURCES_BAK" ]; then
    cp -f "$SOURCES" "$SOURCES_BAK"
  fi
  printf 'deb %s stable main\n' "$APT_MIRROR" > "$SOURCES"
  info "已将 apt 主源切换为清华 TUNA"
}

restore_sources() {
  if [ -f "$SOURCES_BAK" ]; then
    cp -f "$SOURCES_BAK" "$SOURCES"
    info "已恢复安装前的 apt 主源"
  else
    printf 'deb %s stable main\n' "$APT_OFFICIAL" > "$SOURCES"
    info "已恢复官方 apt 主源"
  fi
}

switch_to_tuna
export TERMUX_PKG_NO_MIRROR_SELECT=1
if ! pkg update -y "${APT_OPTS[@]}" </dev/null; then
  warn "TUNA 源更新失败，回退官方源"
  restore_sources
  pkg update -y "${APT_OPTS[@]}" </dev/null || die "官方源 apt update 失败，请检查网络"
fi

# 前置全量升级：同步 libc++（patchelf 0.19.2 依赖 libc++ 30 才有的 __hash_memory 符号）
info "全量升级以同步 libc++（修复 patchelf 链接符号缺失）..."
pkg upgrade -y "${APT_OPTS[@]}" </dev/null || die "pkg upgrade 失败，无法同步 libc++，请检查网络/源"

# ---------------------------------------------------------------- 安装依赖
install_deps() (
  set -e
  pkg install -y "${APT_OPTS[@]}" nodejs binutils patchelf tar ca-certificates </dev/null
  pkg install -y "${APT_OPTS[@]}" glibc-repo </dev/null
  pkg update -y "${APT_OPTS[@]}" </dev/null
  pkg install -y "${APT_OPTS[@]}" glibc openssl-glibc </dev/null
)

info "安装依赖（nodejs、patchelf、binutils、llvm、glibc 等）..."
if ! install_deps; then
  warn "依赖安装失败，重试一次..."
  install_deps || die "依赖安装失败，请检查上方日志后重试"
fi

command -v node >/dev/null 2>&1 || die "nodejs 安装失败"
command -v npm >/dev/null 2>&1 || die "npm 安装失败"
command -v patchelf >/dev/null 2>&1 || die "patchelf 安装失败"

# wrapper 的 verifyInterpreter 依赖 readelf；Termux 的 binutils 只提供 greadelf，
# readelf 由 llvm 包提供。缺失时自动安装 llvm，仍失败则回退 greadelf 软链接。
ensure_readelf() {
  command -v readelf >/dev/null 2>&1 && return 0

  info "未找到 readelf，自动安装 llvm..."
  pkg install -y "${APT_OPTS[@]}" llvm </dev/null || warn "llvm 安装失败，尝试 greadelf 兜底"
  command -v readelf >/dev/null 2>&1 && return 0

  if ! command -v greadelf >/dev/null 2>&1; then
    warn "未找到 greadelf，尝试安装 binutils..."
    pkg install -y "${APT_OPTS[@]}" binutils </dev/null || true
  fi
  if command -v greadelf >/dev/null 2>&1; then
    ln -sf "$(command -v greadelf)" "$PREFIX/bin/readelf"
    info "已自动创建 readelf -> greadelf 软链接"
    return 0
  fi
  return 1
}

ensure_readelf || die "readelf 自动安装失败（llvm 与 greadelf 均不可用），请检查网络/源后重试"
ok "依赖安装完成（node $(node -v)）"

# ---------------------------------------------------------------- 解析版本
resolve_version() {
  local registry="$1" ver
  ver="$(npm view @bash0816/opencode-termux version --registry "$registry" 2>/dev/null </dev/null | tr -d '[:space:]')" || return 1
  [ -n "$ver" ] || return 1
  npm view "@opencode/cli-linux-arm64@${ver}" version --registry "$registry" >/dev/null 2>&1 </dev/null || return 1
  printf '%s' "$ver"
}

info "解析最新版本..."
NPM_REGISTRY="$NPM_MIRROR"
VER="$(resolve_version "$NPM_MIRROR" || true)"
if [ -z "$VER" ]; then
  warn "npmmirror 上缺少完整版本信息，回退官方 npm 源"
  NPM_REGISTRY="$NPM_OFFICIAL"
  VER="$(resolve_version "$NPM_OFFICIAL" || true)"
fi
[ -n "$VER" ] || die "无法获取最新版本，请检查网络"
ok "目标版本: $VER"

NPM_PREFIX="$(npm config get prefix 2>/dev/null </dev/null || true)"
if [ -z "$NPM_PREFIX" ] || [ "$NPM_PREFIX" = "undefined" ]; then
  NPM_PREFIX="$PREFIX"
fi

# ---------------------------------------------------------------- 安装适配层
info "安装 @bash0816/opencode-termux@$VER ..."
npm install -g --no-fund --no-audit --registry "$NPM_REGISTRY" \
  "@bash0816/opencode-termux@$VER" </dev/null

LAUNCHER="$NPM_PREFIX/lib/node_modules/@bash0816/opencode-termux/bin/opencode-termux"
DOWNLOADER="$NPM_PREFIX/lib/node_modules/@bash0816/opencode-termux/lib/downloader.js"
[ -f "$LAUNCHER" ] || die "未找到启动脚本: $LAUNCHER"
[ -f "$DOWNLOADER" ] || die "未找到下载器: $DOWNLOADER"

# npm 包里是 #!/usr/bin/env node，Android 没有 /usr/bin/env
if command -v termux-fix-shebang >/dev/null 2>&1; then
  termux-fix-shebang "$LAUNCHER" </dev/null
else
  node - "$LAUNCHER" "$PREFIX" <<'NODE'
const fs = require('fs');
const [file, prefix] = process.argv.slice(2);
let s = fs.readFileSync(file, 'utf8');
if (s.startsWith('#!/usr/bin/env ')) {
  s = s.replace(/^#!\/usr\/bin\/env /, `#!${prefix}/bin/env `);
  fs.writeFileSync(file, s);
}
NODE
fi

case "$(head -n1 "$LAUNCHER")" in
  "#!$PREFIX/bin/env "*) ;;
  *) die "shebang 修复失败: $(head -n1 "$LAUNCHER")" ;;
esac
ok "shebang 修复完成"

# 把二进制下载地址切到当前 registry
patch_downloader() {
  local registry="$1"
  node - "$DOWNLOADER" "$registry" <<'NODE'
const fs = require('fs');
const [file, registry] = process.argv.slice(2);
let s = fs.readFileSync(file, 'utf8');
const re = /const REGISTRY = '[^']+';/;
if (!re.test(s)) {
  console.error('downloader.js: REGISTRY 行未找到');
  process.exit(1);
}
const next = `const REGISTRY = '${registry}';`;
if (!s.includes(next)) {
  s = s.replace(re, next);
  fs.writeFileSync(file, s);
}
NODE
}

patch_downloader "$NPM_REGISTRY"

# ---------------------------------------------------------------- 首次下载
info "首次启动：下载并校验官方二进制（约 200 MB，请耐心等待）..."
if ! opencode --version </dev/null; then
  warn "使用当前源下载失败，回退官方 npm 源重试"
  patch_downloader "$NPM_OFFICIAL"
  opencode --version </dev/null || die "二进制下载或校验失败"
fi

# ---------------------------------------------------------------- 修补启动脚本
info "修补启动脚本（清理子进程环境）..."
cp -f "$LAUNCHER" "$LAUNCHER.opencode-v2.bak"
node - "$LAUNCHER" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
let s = fs.readFileSync(file, 'utf8');
let changed = false;

function replaceOnce(from, to, marker, label) {
  if (marker && s.includes(marker)) return;
  if (!s.includes(from)) throw new Error(label + ': 目标代码未找到');
  s = s.replace(from, to);
  changed = true;
}

// 1) 引入 glibc loader 路径
replaceOnce(
  "const { GLIBC_LIB_DIR } = require('../lib/patcher');",
  "const { GLIBC_LD_PATH, GLIBC_LIB_DIR } = require('../lib/patcher');",
  "GLIBC_LD_PATH, GLIBC_LIB_DIR",
  '导入 GLIBC_LD_PATH'
);

// 2) 不再向进程注入 LD_LIBRARY_PATH，改用 loader --library-path
replaceOnce(
  "  const env = withAutoUpdateEnv({ ...(deps.env || process.env), LD_PRELOAD: '', LD_LIBRARY_PATH: deps.glibcLibDir || GLIBC_LIB_DIR });\n  try { execFn(binPath, args, { stdio: 'inherit', env }); }",
  "  const env = withAutoUpdateEnv({ ...(deps.env || process.env) });\n  try { execFn(GLIBC_LD_PATH, ['--library-path', deps.glibcLibDir || GLIBC_LIB_DIR, binPath, ...args], { stdio: 'inherit', env }); }",
  "execFn(GLIBC_LD_PATH,",
  'loader 启动'
);

// 3) 禁用 wrapper 自带的 update（会覆盖补丁）
replaceOnce(
  "  if (routed.kind === 'update') {\n    await (deps.runUpdate || runUpdate)(routed.rest, { fs, currentVersion: pkg.version,\n      spawnSync: deps.spawnSync || child.spawnSync, registryGet: deps.registryGet, packageRoot: deps.packageRoot || packageRoot, libPath: deps.libPath || path.resolve(__dirname, '..', 'lib'),\n      write: output, exit }); return;\n  }",
  "  if (routed.kind === 'update') {\n    output('更新请重新运行安装脚本 install-opencode-v2.sh' + String.fromCharCode(10)); exit(1); return;\n  }",
  "更新请重新运行安装脚本",
  'update 路由'
);

if (changed) fs.writeFileSync(file, s);
NODE

if ! opencode --version >/dev/null 2>&1 </dev/null; then
  warn "补丁后的启动脚本运行失败，恢复原版"
  cp -f "$LAUNCHER.opencode-v2.bak" "$LAUNCHER"
  opencode --version >/dev/null 2>&1 </dev/null || true
  die "启动脚本补丁失败"
fi

grep -q "execFn(GLIBC_LD_PATH," "$LAUNCHER" || die "补丁校验失败"
if grep -q "LD_LIBRARY_PATH: deps.glibcLibDir" "$LAUNCHER"; then
  die "补丁校验失败：仍在注入 LD_LIBRARY_PATH"
fi
ok "启动脚本补丁完成"

# ---------------------------------------------------------------- oc 入口
info "创建 oc 入口..."
printf '#!%s/bin/bash\nexec opencode "$@"\n' "$PREFIX" > "$PREFIX/bin/oc"
chmod 755 "$PREFIX/bin/oc"

# ---------------------------------------------------------------- 自检
info "自检..."
VERSION_OUT="$(opencode --version 2>&1 </dev/null | tail -n1 || true)"
printf '  opencode --version: %s\n' "$VERSION_OUT"
case "$VERSION_OUT" in
  *"$VER"*) ok "版本校验通过" ;;
  *) warn "版本输出中未找到 $VER，请手动确认" ;;
esac

oc --version >/dev/null 2>&1 </dev/null || die "oc 入口不可用"
ok "oc 入口正常"

bash -lc 'echo bash-ok' >/dev/null 2>&1 </dev/null || die "bash 自检失败"
ok "bash 自检通过"

if command -v git >/dev/null 2>&1; then
  if git --version >/dev/null 2>&1; then ok "git 正常"; else warn "git 运行异常"; fi
fi
if command -v rg >/dev/null 2>&1; then
  if rg --version >/dev/null 2>&1; then ok "rg 正常"; else warn "rg 运行异常"; fi
fi

cat <<EOF

============================================================
安装完成
  版本 : $VER
  入口 : opencode / oc
  更新 : 重新运行本脚本

如果当前有正在运行的 opencode，请完全退出后重新启动，
新的环境补丁才会生效（已保存的会话不受影响）。
============================================================
EOF
