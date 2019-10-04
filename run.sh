#!/usr/bin/env bash

OURDIR="${BASH_SOURCE%/*}"
cd "$OURDIR"
while true; do
    ./derpibooru_bot.rb
    echo ============== restart ==============
    sleep 1
done
