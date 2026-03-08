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
add_feed chinadns_ng 'https://github.com/zfl9/chinadns-ng;master' # <-- 修复：正确的分支是 master
add_feed ddnsgo 'https://github.com/sirpdboy/luci-app-ddns-go'

sed -i 's/KERNEL_PATCHVER:=./KERNEL_PATCHVER:=6.12/' target/linux/x86/Makefile
sed -i 's/KERNEL_TESTING_PATCHVER:=./KERNEL_TESTING_PATCHVER:=6.12/' target/linux/x86/Makefile

mkdir -p package/passwall-force-latest
cat >> package/passwall-force-latest/Makefile <<'EOF'
# 修复了 awk 后面多余空格导致的语法错误
PKG_SOURCE_VERSION:=$(shell git ls-remote https://github.com/Openwrt-Passwall/openwrt-passwall-packages HEAD | awk '{print $$1}')
EOF
