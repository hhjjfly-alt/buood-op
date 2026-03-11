#!/bin/bash

set -e  
export GIT_TERMINAL_PROMPT=0  

clone_or_pull() {
    local repo=$1 dir=$2 branch=${3:-}
    if [[ -d "$dir/.git" ]]; then
        echo "Update $dir ..."
        git -C "$dir" fetch --depth 1
        if [ -n "$branch" ]; then
            git -C "$dir" reset --hard origin/$branch
        else
            git -C "$dir" reset --hard origin/HEAD
        fi
    else
        echo "Clone $repo -> $dir ..."
        if [ -n "$branch" ]; then
            git clone --depth 1 -b $branch "$repo" "$dir"
        else
            git clone --depth 1 "$repo" "$dir"
        fi
    fi
}

echo "=== 开始执行 diyyb-part2.sh ==="

# 1. 添加 iStore 软件中心源
if ! grep -q '^src-git istore' feeds.conf.default; then
    echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
    ./scripts/feeds update istore
    ./scripts/feeds install -d y -p istore luci-app-store
fi

# 2. 清理默认依赖，为 PassWall 及其组件腾出干净空间
echo "清理默认依赖..."
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/istore_packages/luci-app-zerotier package/feeds/istore_packages/luci-app-zerotier

# 3. 拉取 PassWall
echo "拉取 PassWall..."
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages
rm -rf package/pw-luci/shadowsocksr-libev

# 4. 强制 sing-box 自动同步官方最新版本号
echo "正在获取 SagerNet/sing-box 最新版本号..."
SING_BOX_LATEST=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')

if [ -n "$SING_BOX_LATEST" ] && [ -f "package/pw-luci/sing-box/Makefile" ]; then
    echo "发现 sing-box 官方最新版本: $SING_BOX_LATEST"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/pw-luci/sing-box/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/pw-luci/sing-box/Makefile
else
    echo "获取 sing-box 版本失败或 Makefile 不存在，将使用备用默认版本。"
fi

# 5. 修改 IP 地址
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate

# 6. 修复 smartdns (拉取最新的 luci-app-smartdns 放入 package 目录)
echo "处理 smartdns 和 luci-app-smartdns..."
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' feeds/packages/net/smartdns/Makefile
# 【修复点】官方 OpenWrt master 源码必须使用 JS 版本的 luci-app-smartdns 的 master 分支，直接放在 package 目录下
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master

# 7. 拉取 Lucky 和 Dockerman
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# 8. 拉取 dae 和 zerotier
echo "拉取 dae 和 zerotier..."
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

# 9. 其他组件
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/yingziwu/openwrt-fakehttp package/openwrt-fakehttp
clone_or_pull https://github.com/yingziwu/luci-app-fakehttp package/luci-app-fakehttp

# 10. 【彻底修复 FakeSIP 编译崩溃】使用符合 OpenWrt 规范的完整 Makefile
echo "生成 FakeSIP 标准 OpenWrt 跨架构 Makefile..."
mkdir -p package/fakesip
cat > package/fakesip/Makefile <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=fakesip
PKG_VERSION:=0.9.1
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/MikeWang000000/FakeSIP.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/fakesip
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Disguise UDP traffic as SIP protocol
  URL:=https://github.com/MikeWang000000/FakeSIP
  DEPENDS:=+libnetfilter-queue +libmnl +libnfnetlink +kmod-ipt-nfqueue +iptables-mod-nfqueue
endef

define Package/fakesip/description
  Disguise your UDP traffic as SIP protocol to evade DPI detection, using Netfilter Queue.
endef

# 取消手动指定编译命令，依赖 OpenWrt 内置宏自动映射 C 编译器与动态库，杜绝缺少依赖包导致的报错

define Package/fakesip/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/fakesip $(1)/usr/bin/
endef

$(eval $(call BuildPackage,fakesip))
EOF

# 11. 系统优化
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile

echo "=== diyyb-part2.sh 执行完成 ==="
