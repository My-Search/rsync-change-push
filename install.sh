#!/bin/bash
set -e  # 遇到错误时退出脚本

# 函数：显示错误信息并退出
error_exit() {
    echo "$1" 1>&2
    exit 1
}

# 通用核心函数：包管理器检测和软件安装
# 参数1：要安装的软件包列表，空格分隔
# 参数2：是否是远程环境（1=远程，0=本地）
core_install_packages() {
    local packages="$1"
    local is_remote=$2
    local PM=""
    local SUDO="sudo"
    
    # 检测包管理器类型
    if command -v yum &> /dev/null; then
        PM="yum"                  # RHEL/CentOS/Fedora
    elif command -v dnf &> /dev/null; then
        PM="dnf"                  # 较新的Fedora/RHEL
    elif command -v apt-get &> /dev/null; then
        PM="apt-get"              # Debian/Ubuntu
    elif command -v pacman &> /dev/null; then
        PM="pacman"               # Arch Linux
    elif command -v zypper &> /dev/null; then
        PM="zypper"               # openSUSE
    else
        echo "错误：未找到支持的包管理器"
        return 1
    fi

    echo "检测到包管理器: $PM，安装软件包: $packages"
    
    # 根据不同包管理器执行安装命令
    case $PM in
        yum|dnf)
            $SUDO $PM install -y $packages
            ;;
        apt-get)
            $SUDO $PM update -y > /dev/null
            $SUDO $PM install -y $packages
            ;;
        pacman)
            $SUDO $PM -Sy --noconfirm $packages
            ;;
        zypper)
            $SUDO $PM install -y $packages
            ;;
    esac

    # 验证所有软件包是否安装成功
    local missing=0
    for pkg in $packages; do
        # 对于inotify-tools，实际命令是inotifywait
        local cmd=$pkg
        if [ "$pkg" = "inotify-tools" ]; then
            cmd="inotifywait"
        fi
        
        if ! command -v $cmd &> /dev/null; then
            echo "错误：$pkg 安装失败"
            missing=1
        fi
    done
    
    return $missing
}

# 本地安装包装器
install_local_packages() {
    local packages="$1"
    echo "=== 开始安装本地软件包: $packages ==="
    if ! core_install_packages "$packages" 0; then
        error_exit "错误：本地软件包安装失败"
    fi
    echo "=== 本地软件包安装完成 ==="
}

# 远程安装包装器
install_remote_packages() {
    local remote_ip=$1
    local packages=$2
    
    echo "=== 开始在远程服务器 $remote_ip 安装软件包: $packages ==="
    
    # 将核心安装函数和调用逻辑通过SSH传递到远程执行
    REMOTE_SCRIPT=$(cat << EOF
$(declare -f core_install_packages)  # 导入核心安装函数
core_install_packages "$packages" 1  # 执行远程安装，第二个参数为1表示远程环境
EOF
)

    # 通过SSH执行远程安装
    ssh -o StrictHostKeyChecking=no root@$remote_ip "$REMOTE_SCRIPT" || {
        error_exit "错误：远程服务器 $remote_ip 软件包安装失败"
    }
    
    echo "=== 远程服务器 $remote_ip 软件包安装完成 ==="
}

# 函数：安装本地依赖
install_local_dependencies() {
    install_local_packages "inotify-tools rsync"
}

# 函数：远程安装rsync
install_remote_rsync() {
    local remote_ip=$1
    install_remote_packages "$remote_ip" "rsync"
}

# 主程序开始
echo "===== 开始配置rsync自动同步服务 ====="

# 1. 安装本地依赖
install_local_dependencies

# 2. 获取用户输入
echo -n "请输入需要监控的本地目录路径 (例如: /root/Xboard)："
read watch_dir

# 验证本地目录是否存在
if [ ! -d "$watch_dir" ]; then
    error_exit "错误：输入的本地目录 $watch_dir 不存在"
fi

echo -n "请输入目标服务器的IP地址 (例如: 205.198.65.168)："
read push_to

echo -n "请输入目标服务器上的备份路径 (例如: /opt/Xboard_backup/)："
read push_to_path

# 3. 检查rsync-active-push.sh脚本是否存在
if [ ! -f "./rsync-active-push.sh" ]; then
    error_exit "错误：当前目录下未找到rsync-active-push.sh脚本"
fi

# 4. 更新rsync-active-push.sh文件中的变量值
sed -i "s|^watch_dir=.*|watch_dir=$watch_dir|" ./rsync-active-push.sh || {
    error_exit "错误：更新watch_dir失败"
}
sed -i "s|^push_to=.*|push_to=$push_to|" ./rsync-active-push.sh || {
    error_exit "错误：更新push_to失败"
}
sed -i "s|^push_to_path=.*|push_to_path=$push_to_path|" ./rsync-active-push.sh || {
    error_exit "错误：更新push_to_path失败"
}

echo "rsync-active-push.sh 配置更新成功！"

# 5. 部署脚本到指定目录
mkdir -p /opt/rsync-script/ || error_exit "错误：创建/opt/rsync-script目录失败"
cp ./rsync-active-push.sh /opt/rsync-script/ || error_exit "错误：复制脚本失败"
chmod +x /opt/rsync-script/rsync-active-push.sh || error_exit "错误：设置脚本执行权限失败"

# 6. 生成SSH密钥并分发
echo "=== 配置SSH无密码登录 ==="
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "生成SSH密钥对..."
    ssh-keygen -t rsa -b 2048 -N "" -f ~/.ssh/id_rsa -q || {
        error_exit "错误：生成SSH密钥失败"
    }
fi

echo "将SSH公钥发送到目标服务器..."
ssh-copy-id -o StrictHostKeyChecking=no root@$push_to || {
    error_exit "错误：发送SSH公钥到目标服务器失败，请手动配置无密码登录"
}

# 7. 远程安装rsync
install_remote_rsync $push_to

# 8. 创建并配置systemd服务
echo "=== 配置系统服务 ==="
sudo bash -c "cat > /etc/systemd/system/rsync-active-push.service <<EOF
[Unit]
Description=rsync-active-push service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /opt/rsync-script/rsync-active-push.sh
Restart=on-failure
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF" || error_exit "错误：创建系统服务文件失败"

# 9. 启动并启用服务
systemctl daemon-reload || error_exit "错误：重新加载systemd失败"
systemctl enable rsync-active-push.service || error_exit "错误：设置服务开机启动失败"
systemctl start rsync-active-push.service || error_exit "错误：启动服务失败"

# 10. 显示服务状态
echo "=== 服务配置完成 ==="
echo "当前服务状态："
systemctl status rsync-active-push.service --no-pager

echo "===== rsync自动同步服务配置完成 ====="
echo "监控目录: $watch_dir"
echo "目标服务器: $push_to"
echo "目标路径: $push_to_path"
