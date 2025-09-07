#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
# MIT License
# 描述: OpenWrt DIY script part 2 (After Update feeds)

# 1. 修改默认 IP / 主机名 / 固件名 / 版本号
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk
pushd package/lean/default-settings/files
sed -i '/http/d' zzz-default-settings
orig_version="$(grep DISTRIB_REVISION zzz-default-settings | awk -F"'" '{print $2}')"
sed -i "s/${orig_version}/${orig_version} ($(date +%Y-%m-%d))/g" zzz-default-settings
popd

# 2. 强制重新下载 PassWall 组件源码（确保每次都用上游最新）
rm -rf feeds/passwall_packages/* feeds/passwall_luci/*

# 3. SmartDNS 版本 bump（可选）
sed -i 's/1.2024.45/1.2024.46/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/b525170bfd627607ee5ac81f97ae0f1f4f087d6b/g; /^PKG_MIRROR_HASH/s/^/#/' \
       feeds/packages/net/smartdns/Makefile

# 4. 额外插件（按需保留）
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky
pushd package/lean
git clone --depth=1 https://github.com/lisaac/luci-app-dockerman
popd

# 5. 连接数优化
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
