# 1. 下载脚本（-L 参数跟随重定向，避免下载空文件）
curl -L -o install-opencode.sh https://raw.githubusercontent.com/motiyo/opencode-termux/refs/heads/main/install-opencode-termux.sh

# 2. 添加执行权限
chmod +x install-opencode.sh

# 3. 运行安装（构建约需 5-10 分钟）
bash install-opencode.sh
