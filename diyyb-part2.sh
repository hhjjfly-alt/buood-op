#!/bin/bash

clone_or_pull() {
local repo=$1 dir=$2
if [[ -d "$dir/.git" ]]; then
echo "Update $dir ..."
git -C "$dir" fetch --depth 1
git -C "$dir" reset --hard origin/HEAD
else
echo "Clone $repo -> $dir ..."
git clone --depth 1 "$repo" "$dir"
fi
}

# 1. 添加 iStore 软件中心源
grep -q '^src-git istore' feeds.conf.default || {
echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
./scripts/feeds update istore
./scripts/feeds install -d y -p istore luci-app-store
}

# 2. 清理默认依赖，为最新插件腾出纯净空间
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 彻底删除 istore_packages 源里陈旧且不兼容的 luci-app-zerotier
rm -rf feeds/istore_packages/luci-app-zerotier package/feeds/istore_packages/luci-app-zerotier

# 3. 拉取 PassWall 及相关依赖
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages
rm -rf feeds/chinadns_ng/* feeds/passwall_packages/* feeds/passwall_luci/*

# -------------------------------------------------------------
# 【终极防线】防死灰复燃：物理删除 SSR，并强制关闭默认的客户端加载！
# -------------------------------------------------------------
rm -rf package/pw-luci/shadowsocksr-libev
echo "# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client is not set" >> .config
echo "# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Server is not set" >> .config
# -------------------------------------------------------------

# 4. 拉取 sing-box 与基础网络配置修改
rm -rf feeds/packages/net/sing-box package/sing-box
clone_or_pull https://github.com/sbwml/openwrt-sing-box package/sing-box
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk

# 5. 屏蔽旧版 smartdns 的强行校验
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' feeds/packages/net/smartdns/Makefile

# 6. 拉取 Lucky 和 Dockerman
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# -------------------------------------------------------------
# 🚨 终极环境修复：提取 ImmortalWrt 标准版 dae 及 zerotier
# -------------------------------------------------------------
rm -rf package/dae package/luci-app-dae package/luci-app-zerotier
git clone --depth=1 https://github.com/immortalwrt/packages package/immortalwrt-packages
mv package/immortalwrt-packages/net/dae package/dae
rm -rf package/immortalwrt-packages

sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile

git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci
mv package/immortalwrt-luci/applications/luci-app-dae package/luci-app-dae
mv package/immortalwrt-luci/applications/luci-app-zerotier package/luci-app-zerotier
rm -rf package/immortalwrt-luci

rm -rf package/luci-app-dae/dae

echo "CONFIG_DEVEL=y" >> .config
echo "CONFIG_BPF_TOOLCHAIN_HOST=y" >> .config
# -------------------------------------------------------------

# 7. 各种扩展环境与组件
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/yingziwu/openwrt-fakehttp package/openwrt-fakehttp
clone_or_pull https://github.com/yingziwu/luci-app-fakehttp package/luci-app-fakehttp

# 8. 修复 FakeSIP 编译无 Go Module 的问题
clone_or_pull https://github.com/MikeWang000000/FakeSIP package/fakesip
pushd package/fakesip
go mod init fakesip || true
go mod tidy || true
go build -o fakesip || true
mkdir -p ../base-files/files/usr/bin/
cp fakesip ../base-files/files/usr/bin/ || true
popd

# 9. 杂项系统与终端优化
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile
