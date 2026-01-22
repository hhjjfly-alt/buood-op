#!/bin/bash
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
# MIT License
# 描述: OpenWrt DIY script part 1 (Before Update feeds)

# 仅在主脚本导出 add_feed_unique 后生效，云编译可安全忽略
if command -v add_feed_unique >/dev/null 2>&1; then
    # 幂等添加 iStore 及相关源
    add_feed_unique istore          'https://github.com/linkease/istore;main'
    add_feed_unique istore_packages 'https://github.com/linkease/istore-packages;main'
    add_feed_unique smartdns_luci   'https://github.com/pymumu/luci-app-smartdns;lede'

    # 幂等添加官方 Passwall 源 (这会自动获得高优先级)
    add_feed_unique passwall_packages 'https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main'
    add_feed_unique passwall_luci      'https://github.com/Openwrt-Passwall/openwrt-passwall.git;main'

    # 幂等添加官方 ChinaDNS-NG 源 (这也会自动获得高优先级)
    add_feed_unique chinadns_ng 'https://github.com/zfl9/chinadns-ng;main'
fi

# 移除所有破坏 Feed 优先级的复杂操作，因为 add_feed_unique 已经正确处理了所有情况。

########### 内核版本（可选） ###########
sed -i 's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/' target/linux/x86/Makefile

########### 强制刷新二进制版本（可选，但推荐保留） ###########
# 在 feeds 安装完成后、make menuconfig 之前执行
cat >> ./package/lean/passwall-force-latest.mk <<'EOF'
# 强制使用上游最新 commit，不缓存旧版本
PKG_SOURCE_VERSION:=$(shell git ls-remote https://github.com/Openwrt-Passwall/openwrt-passwall-packages HEAD | awk '{print $$1}')
EOF
