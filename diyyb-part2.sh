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
grep -q '^src-git istore' feeds.conf.default || {
echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
./scripts/feeds update istore
./scripts/feeds install -d y -p istore luci-app-store
}
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git  package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git   package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages
rm -rf feeds/chinadns_ng/* feeds/passwall_packages/* feeds/passwall_luci/*
rm -rf feeds/packages/net/sing-box package/sing-box
clone_or_pull https://github.com/sbwml/openwrt-sing-box package/sing-box
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-  $(shell date +%Y%m%d)-$  (VERSION_DIST_SANITIZED)/g' include/image.mk
pushd package/base-files/files/bin
sed -i '/http/d' zzz-default-settings
orig_version="$(grep DISTRIB_REVISION= zzz-default-settings | awk -F"'" '{print $2}')"
sed -i "s/  ${orig_version}/$  {orig_version} ($(date +%Y-%m-%d))/g" zzz-default-settings
popd
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' 
feeds/packages/net/smartdns/Makefile
clone_or_pull https://github.com/gdy666/luci-app-lucky.git  package/lucky
pushd package/luci/applications
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git luci-app-dockerman
popd
clone_or_pull https://github.com/sbwml/luci-app-dae package/dae
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
pushd feeds/packages/utils/cgroupfs-mount
curl -s https://raw.githubusercontent.com/sbwml/luci-app-dae/main/.cgroupfs/cgroupfs-mount.init.patch | patch -p1
curl -s https://raw.githubusercontent.com/sbwml/luci-app-dae/main/.cgroupfs/900-add-cgroupfs2.patch > patches/900-add-cgroupfs2.patch
popd
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/yingziwu/openwrt-fakehttp package/openwrt-fakehttp
clone_or_pull https://github.com/yingziwu/luci-app-fakehttp package/luci-app-fakehttp
clone_or_pull https://github.com/MikeWang000000/FakeSIP package/fakesip
pushd package/fakesip
go build -o fakesip
popd
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="  $\033[01;32m$  \u@\h  $\033[00m$  :  $\033[01;34m$  \w  $\033[00m$  $ "' >> package/base-files/files/etc/profile