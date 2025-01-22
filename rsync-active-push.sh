#!/bin/bash
 
###########################################################
#  description: inotify+rsync best practice               #
#  author     : 骏马金龙                                   #
#  blog       : http://www.cnblogs.com/f-ck-need-u/       #
###########################################################
 
watch_dir=/root/Xboard

push_to=205.198.65.168
push_to_path=/opt/Xboard_backup/
 
# First to do is initial sync
rsync -az --delete --exclude="*.swp" --exclude="*.swx" $watch_dir $push_to:/tmp
 
inotifywait -mrq -e delete,close_write,moved_to,moved_from,isdir --timefmt '%Y-%m-%d %H:%M:%S' --format '%w%f:%e:%T' $watch_dir \
--exclude=".*.swp" >>/etc/inotifywait.log &
 
while true;do
     if [ -s "/etc/inotifywait.log" ];then
        grep -i -E "delete|moved_from" /etc/inotifywait.log >> /etc/inotify_away.log
        rsync -az --delete --exclude="*.swp" --exclude="*.swx" $watch_dir $push_to:/tmp
        if [ $? -ne 0 ];then
           echo "$watch_dir sync to $push_to failed at `date +"%F %T"`,please check it by manual" |\
           mail -s "inotify+Rsync error has occurred" root@localhost
        fi
        cat /dev/null > /etc/inotifywait.log
        rsync -az --delete --exclude="*.swp" --exclude="*.swx" $watch_dir $push_to:$push_to_path
    else
        sleep 1
    fi
done
