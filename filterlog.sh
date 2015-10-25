#!/bin/bash
for i; do
    echo "$i" # [2015-10-11 11:51:49 +0000
    sed -r -i.bak '/^\[[0-9-]{10} [0-9:]{8} \+0000 ERROR\] !!! <> #<Telegram::Bot::Exceptions::ResponseError: Telegram API has returned the error. \(error_code: "50[24]", uri: "https:\/\/api.telegram.org\/bot114516473:AAGkuwBYAzLyXn35AMqkvVLuCXrJIhykUBE\/getUpdates"\)>$/d' "$i"
done
