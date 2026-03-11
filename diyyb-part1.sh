#!/bin/bash
add_feed() {
local name=$1 url=$2
if ! grep -q "^src-git $name " feeds.conf.default; then
echo "src-git $name $url" >> feeds.conf.default
fi
}

add_feed istore 'https://github.com/linkease/istore;main'
add_feed istore_packages 'https://github.com/linkease/istore-packages;main'
add_feed smartdns_luci 'https://github.com/pymumu/luci-app-smartdns;lede'
