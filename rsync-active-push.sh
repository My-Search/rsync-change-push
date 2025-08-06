#!/bin/bash

###########################################################
#  description: inotify+rsync best practice               #
#  author     : 骏马金龙                                   #
#  blog       : http://www.cnblogs.com/f-ck-need-u/       #
###########################################################

watch_dir=/opt/frp
push_to=192.3.250.100
push_to_path=/opt/jp2

# 1. 启动时先执行一次完整同步（确保初始状态一致）
echo "Initial sync starting at $(date +"%F %T")..."
rsync -az --delete --exclude="*.swp" --exclude="*.swx" "$watch_dir" "$push_to:$push_to_path"

# 检查初始同步是否成功
if [ $? -ne 0 ]; then
    echo "Initial sync failed at $(date +"%F %T"), please check manually" | mail -s "Initial Sync Error" root@localhost
    exit 1
fi
echo "Initial sync completed at $(date +"%F %T")"

# 2. 启动inotifywait监听目录变化，记录事件到日志
inotifywait -mrq -e delete,close_write,moved_to,moved_from,isdir \
    --timefmt '%Y-%m-%d %H:%M:%S' \
    --format '%w%f:%e:%T' \
    "$watch_dir" \
    --exclude=".*.swp" >> /etc/inotifywait.log &

# 3. 循环检查日志，有变化时执行同步
while true; do
    if [ -s "/etc/inotifywait.log" ]; then
        # 记录删除/移动事件到单独日志（可选）
        grep -i -E "delete|moved_from" /etc/inotifywait.log >> /etc/inotify_away.log
        
        # 执行同步操作
        echo "Detected changes, syncing at $(date +"%F %T")..."
        rsync -az --delete --exclude="*.swp" --exclude="*.swx" "$watch_dir" "$push_to:$push_to_path"
        
        # 检查同步结果，失败则发邮件通知
        if [ $? -ne 0 ]; then
            echo "$watch_dir sync to $push_to failed at $(date +"%F %T"), please check manually" | \
            mail -s "inotify+Rsync Sync Error" root@localhost
        fi
        
        # 清空日志，准备记录下一批变化
        cat /dev/null > /etc/inotifywait.log
    else
        # 无变化时休眠1秒，减少资源占用
        sleep 1
    fi
done
