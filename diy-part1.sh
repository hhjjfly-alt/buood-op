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

########### 1. 内核版本（可选） ###########
sed -i 's/KERNEL_PATCHVER:=.*/KERNEL_PATCHVER:=6.12/' target/linux/x86/Makefile

########### 2. 官方 Passwall 源（优先级最高） ###########
# 函数由主脚本 Build_x86OpenWrt.sh 导出，幂等添加
if command -v add_feed_unique >/dev/null 2>&1; then
    # 核心二进制仓库（含 Xray/Sing-Box/Hysteria/ChinaDNS-NG/Geoview 等）
    add_feed_unique passwall_packages 'https://github.com/xiaorouji/openwrt-passwall-packages;main'
    # LuCI 界面仓库
    add_feed_unique passwall_luci      'https://github.com/xiaorouji/openwrt-passwall;main'
fi

# chinadns-ng  1. 删除 lean 自带的老版本（防止冲突）
sed -i '/^src-git packages/d' feeds.conf.default

# 2. 重新添加 packages 源（保持 lean 其它包）并置顶官方 ChinaDNS-NG
#    注意：packages 必须保留，否则基础包缺失
echo 'src-git packages https://github.com/coolsnowwolf/packages;master' > feeds.conf.default.tmp
cat feeds.conf.default >> feeds.conf.default.tmp
mv feeds.conf.default.tmp feeds.conf.default

# 3. 再追加官方 ChinaDNS-NG 源（优先级高于 packages）
add_feed_unique chinadns_ng 'https://github.com/zfl9/chinadns-ng;main'


########### 3. 每次编译都“强制刷新”一次二进制版本 ###########
# 在 feeds 安装完成后、make menuconfig 之前执行
cat >> ./package/lean/passwall-force-latest.mk <<'EOF'
# 强制使用上游最新 commit，不缓存旧版本
PKG_SOURCE_VERSION:=$(shell git ls-remote https://github.com/xiaorouji/openwrt-passwall-packages HEAD | awk '{print $$1}')
EOF
