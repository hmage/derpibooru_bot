#!/usr/bin/env bash

OURDIR="${BASH_SOURCE%/*}"
cd "$OURDIR"/e621
while true; do
    go build && ./e621
    echo ============== restart ==============
    sleep 1
done
