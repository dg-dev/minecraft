#!/bin/sh

command_path=/opt/minecraft/scripts/command.sh
time_limit_sec=60

backup_state=0
start_epoch=$(date +%s)
start_cursor=$(journalctl -u minecraft.service --show-cursor -n 0 | grep '^-- cursor: ' | cut -f 3 -d ' ')

while [ "$(expr "$(date +%s)" - "$start_epoch")" -lt "$time_limit_sec" ]; do
    [ -z "$start_cursor" ] && exit 1

    if [ "$backup_state" -eq 0 ]; then
        "${command_path}" save resume
        sleep 1
        "${command_path}" save hold
        backup_state=1
    fi

    while read -r LINE; do
        if [ "$(echo "$LINE" | cut -f '1-2' -d ' ')" = '-- cursor:' ]; then
            start_cursor="$(echo "$LINE" | cut -f '3' -d ' ')"
        elif [ "$backup_state" -eq 1 ] && [ ! -z "$(echo "$LINE" | grep 'Saving\.\.\.$')" ]; then
            "${command_path}" save query
            backup_state=2
            echo "LINE (${backup_state}): $LINE"
        elif [ "$backup_state" -eq 2 ] && [ ! -z "$(echo "$LINE" | grep 'Data saved\. Files are now ready to be copied\.$')" ]; then
            backup_state=3
            echo "LINE (${backup_state}): $LINE"
        elif [ "$backup_state" -eq 2 ] && [ ! -z "$(echo "$LINE" | grep 'A previous save has not been completed\.$')" ]; then
            "${command_path}" save query
            echo "LINE (${backup_state}): $LINE"
        elif [ "$backup_state" -eq 3 ]; then
            # check if this is correct data, back up, resume and exit
            "$command_path" save resume
            echo "LINE (${backup_state}): $LINE"
            exit 0
        else
            echo "LINE (${backup_state}): $LINE"
        fi
    done << EOT
$(journalctl -u minecraft.service --after-cursor "$start_cursor" -o cat --no-pager --show-cursor)
EOT
    sleep 1
done

[ "$backup_state" -gt 0 ] && "$command_path" save resume
exit 2
