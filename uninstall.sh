#!/bin/bash

# 停止并禁用服务
echo "正在停止 rsync-active-push 服务..."
sudo systemctl stop rsync-active-push.service
sudo systemctl disable rsync-active-push.service

# 删除服务文件
echo "正在删除 rsync-active-push 服务文件..."
sudo rm -f /etc/systemd/system/rsync-active-push.service

# 删除脚本文件
echo "正在删除脚本文件..."
sudo rm -rf /opt/rsync-script/rsync-active-push.sh

# 删除 SSH 密钥对
echo "是否删除 SSH 密钥对？(y/n)"
read delete_ssh_key
if [ "$delete_ssh_key" == "y" ]; then
    echo "正在删除 SSH 密钥对..."
    rm -f ~/.ssh/id_rsa
    rm -f ~/.ssh/id_rsa.pub
fi

# 重新加载 systemd 配置
echo "正在重新加载 systemd 配置..."
sudo systemctl daemon-reload

# 关闭监听服务
pkill -f inotifywait

# 输出完成信息
echo "卸载完成！"

