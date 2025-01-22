# 提示用户输入变量
echo "请输入watch_dir的路径 (例如: /root/Xboard)："
read watch_dir

echo "请输入push_to的IP地址 (例如: 205.198.65.168)："
read push_to

echo "请输入push_to_path的路径 (例如: /opt/Xboard_backup/)："
read push_to_path

# 更新run.sh文件中的变量值
sed -i "s|^watch_dir=.*|watch_dir=$watch_dir|" ./rsync-active-push.sh
sed -i "s|^push_to=.*|push_to=$push_to|" ./rsync-active-push.sh
sed -i "s|^push_to_path=.*|push_to_path=$push_to_path|" ./rsync-active-push.sh

# 输出完成信息
echo "run.sh 配置更新成功！"

mkdir -p /opt/rsync-script/
cp ./rsync-active-push.sh /opt/rsync-script/

ssh-keygen -t rsa -b 2048
ssh-copy-id root@$push_to

sudo bash -c 'cat > /etc/systemd/system/rsync-active-push.service <<EOF
[Unit]
Description=rsync-active-push
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /opt/rsync-script/rsync-active-push.sh
Restart=on-failure
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF'

systemctl start rsync-active-push.service 
systemctl status rsync-active-push.service 
