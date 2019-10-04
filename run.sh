#!/usr/bin/env bash

OURDIR="${BASH_SOURCE%/*}"
cd "$OURDIR"
while true; do
    go build && ./derpibooru_bot
    echo ============== restart ==============
    sleep 1
done
