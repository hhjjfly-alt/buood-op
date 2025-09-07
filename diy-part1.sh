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
    # 如需其它源，继续往下写即可
    # add_feed_unique passwall_packages 'https://github.com/xiaorouji/openwrt-passwall-packages;main'
fi

########### 可选内核版本调整 ###########
sed -i 's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/' target/linux/x86/Makefile
