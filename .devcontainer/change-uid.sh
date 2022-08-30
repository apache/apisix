#!/bin/bash
set -exo pipefail

function change_uid() {
    local uid="$1"
    if [ -z "$uid" ]; then
        echo "Not changing user id"
        return 0
    fi
    local gid="${2:-$uid}"
    usermod --uid "$uid" --gid "$gid" "$USERNAME"
    chown -R "$uid:$gid" "/home/$USERNAME"
}

function change_gid() {
    local gid="$1"
    if [ -z "$gid" ]; then
        echo "Not changing group id"
        return 0
    fi
    groupmod --gid "$CHANGE_USER_GID" "$USERNAME"
}