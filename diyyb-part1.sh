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
add_feed passwall_packages 'https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main'
add_feed passwall_luci 'https://github.com/Openwrt-Passwall/openwrt-passwall.git;main'
add_feed chinadns_ng 'https://github.com/zfl9/chinadns-ng;master'
add_feed ddnsgo 'https://github.com/sirpdboy/luci-app-ddns-go'

# 注意：已移除会导致源码扫描崩溃的残缺 Makefile 生成脚本
