#!/bin/bash
add_feed() {
local name=$1 url=$2
if ! grep -q "^src-git $name " feeds.conf.default; then
echo "src-git $name $url" >> feeds.conf.default
fi
}

# 仅保留核心源，去除会导致 grep target pattern 错误的 smartdns_luci
add_feed istore 'https://github.com/linkease/istore;main'
add_feed istore_packages 'https://github.com/linkease/istore-packages;main'
