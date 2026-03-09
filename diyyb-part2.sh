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

# 1. 添加 iStore 源
grep -q '^src-git istore' feeds.conf.default || {
echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
./scripts/feeds update istore
./scripts/feeds install -d y -p istore luci-app-store
}

# 2. 清理默认依赖，为插件腾出纯净空间
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 3. 拉取 PassWall 和相关依赖
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git  package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git   package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages
rm -rf feeds/chinadns_ng/* feeds/passwall_packages/* feeds/passwall_luci/*

# 4. 拉取 sing-box 与基础修改
rm -rf feeds/packages/net/sing-box package/sing-box
clone_or_pull https://github.com/sbwml/openwrt-sing-box package/sing-box
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk

# 5. 屏蔽旧版 smartdns 的强行校验
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' feeds/packages/net/smartdns/Makefile

# 6. 拉取 Lucky 和 Dockerman (修复了原脚本目录不存在导致的报错)
clone_or_pull https://github.com/gdy666/luci-app-lucky.git  package/lucky
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# -------------------------------------------------------------
# 🚨 完美修复 OpenWrt Master 编译 dae 过程中的解析崩溃问题
# -------------------------------------------------------------
# 抓取 douglarek 专为 OpenWrt master 维护的最新核心包
git clone --depth 1 https://github.com/douglarek/dae-openwrt package/dae-openwrt
cp -r package/dae-openwrt/net/dae package/dae
rm -rf package/dae-openwrt

# 【绝对致命核心修复】修改 Makefile 里的相对路径，适配到真实的 OpenWrt $(TOPDIR) 全局路径！
sed -i 's|.*lang/golang/golang-package.mk|include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile

# 抓取 sbwml 提供的 Web 控制界面，并物理删除其自带的旧核心，杜绝冲突
git clone --depth 1 https://github.com/sbwml/luci-app-dae package/luci-app-dae
rm -rf package/luci-app-dae/dae

# 强制注入编译 dae 需要的 eBPF 宏到配置中
echo "CONFIG_DEVEL=y" >> .config
echo "CONFIG_BPF_TOOLCHAIN_HOST=y" >> .config
# -------------------------------------------------------------

# 7. 各种扩展插件
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/yingziwu/openwrt-fakehttp package/openwrt-fakehttp
clone_or_pull https://github.com/yingziwu/luci-app-fakehttp package/luci-app-fakehttp

# 8. 修复 FakeSIP 编译无 Go Module 的问题，并将其纳入系统固件打包目录
clone_or_pull https://github.com/MikeWang000000/FakeSIP package/fakesip
pushd package/fakesip
go mod init fakesip
go mod tidy
go build -o fakesip
mkdir -p ../base-files/files/usr/bin/
cp fakesip ../base-files/files/usr/bin/
popd

# 9. 杂项系统优化
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile
