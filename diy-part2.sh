#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# Modify default IP
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
# Modify output filename
sed -i 's/IMG_PREFIX:=$(VERSION_DIST_SANITIZED)/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk
# Modify system version
pushd package/lean/default-settings/files
sed -i '/http/d' zzz-default-settings
export orig_version="$(cat "zzz-default-settings" | grep DISTRIB_REVISION= | awk -F "'" '{print $2}')"
sed -i "s/${orig_version}/${orig_version} ($(date +"%Y-%m-%d"))/g" zzz-default-settings
popd

# Passwall
# rm -rf feeds/luci/applications/luci-app-passwall/
# rm -rf feeds/packages/net/xray-core/
# rm -rf feeds/packages/net/xray-plugin/
# git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages package/openwrt-passwall
# git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall package/luci-app-passwall

# 只删除 PassWall 会用到的冲突包
rm -rf feeds/packages/net/xray-core
rm -rf feeds/packages/net/xray-plugin
rm -rf feeds/packages/net/v2ray-core
rm -rf feeds/packages/net/v2ray-plugin
rm -rf feeds/packages/net/sing-box

# 然后拉取 PassWall 的包
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages package/openwrt-passwall
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall package/luci-app-passwall

# Fix ipt2socks download URL
sed -i 's|https://codeload.github.com/zfl9/ipt2socks/tar.gz/v1.1.5?|https://github.com/zfl9/ipt2socks/archive/refs/tags/v1.1.5.tar.gz|' package/openwrt-passwall/ipt2socks/Makefile

# Change kernel version to 6.6
# sed -i 's/KERNEL_PATCHVER:=5.15/KERNEL_PATCHVER:=6.12/g' target/linux/x86/Makefile

# Update SmartDNS version
sed -i 's/1.2024.45/1.2024.46/g' feeds/packages/net/smartdns/Makefile
sed -i 's/9ee27e7ba2d9789b7e007410e76c06a957f85e98/b525170bfd627607ee5ac81f97ae0f1f4f087d6b/g' feeds/packages/net/smartdns/Makefile
sed -i 's/^PKG_MIRROR_HASH/#&/' feeds/packages/net/smartdns/Makefile

# Add extra packages
git clone https://github.com/gdy666/luci-app-lucky.git package/lucky
pushd package/lean
git clone --depth=1 https://github.com/lisaac/luci-app-dockerman
popd

# Correct connection count
sed -i '/customized in this file/a net.netfilter.nf_conntrack_max=165535' package/base-files/files/etc/sysctl.conf

# ---------- iStore 官方源 ----------
echo >> feeds.conf.default
echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
./scripts/feeds update istore
./scripts/feeds install -d y -p istore luci-app-store
