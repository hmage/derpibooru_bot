#!/usr/bin/env bash

OURDIR="${BASH_SOURCE%/*}"
cd "$OURDIR"
while true; do
    ./e621_bot.rb
    sleep 1
done
