#!/bin/bash
#  Part1 – 在 update feeds 之前执行
set -euo pipefail

# 仅在主脚本导出 add_feed_unique 后生效
if command -v add_feed_unique >/dev/null 2>&1; then
    add_feed_unique istore          'https://github.com/linkease/istore;main'
    add_feed_unique istore_packages 'https://github.com/linkease/istore-packages;main'
    add_feed_unique smartdns_luci   'https://github.com/pymumu/luci-app-smartdns;lede'
    add_feed_unique passwall_packages 'https://github.com/xiaorouji/openwrt-passwall-packages;main'
    add_feed_unique passwall_luci      'https://github.com/xiaorouji/openwrt-passwall;main'
    add_feed_unique chinadns_ng       'https://github.com/zfl9/chinadns-ng;main'
fi

# 统一内核版本
sed -i 's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/' target/linux/x86/Makefile

# 删掉 lean 自带会与官方冲突的二进制包
for pkg in chinadns-ng dns2socks geoview hysteria ipt2socks microsocks naiveproxy \
           shadowsocks-libev shadowsocks-rust shadowsocksr-libev simple-obfs sing-box \
           tcping trojan-plus tuic-client v2ray-core v2ray-geodata v2ray-plugin \
           xray-core xray-plugin; do
    rm -rf "feeds/packages/net/$pkg"
done
rm -rf feeds/luci/applications/luci-app-passwall

# 重新写入 packages 源（保证基础包存在）
grep -q '^src-git packages' feeds.conf.default && \
  sed -i '/^src-git packages/d' feeds.conf.default
sed -i '1i\src-git packages https://github.com/coolsnowwolf/packages;master' feeds.conf.default
