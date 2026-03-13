#!/bin/bash
# diyyb1-part2.sh

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

echo "=== 开始执行 diyyb1-part2.sh ==="
# =================================================================
# 1. 终极 A 方案：无视作者排版习惯的“降维打击”修复法
# =================================================================
echo "配置并修复官方 iStore 源..."
if ! grep -q '^src-git istore ' feeds.conf.default; then
    echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
fi
if ! grep -q '^src-git istore_packages ' feeds.conf.default; then
    echo 'src-git istore_packages https://github.com/linkease/istore-packages;main' >> feeds.conf.default
fi

# 第一步：只拉取代码，先不安装
./scripts/feeds update istore istore_packages

echo "执行终极兼容性净化手术..."

# 第一招：无差别摧毁所有带符号的依赖限制
# 效果：luci-lib-taskd (>= 1.0.3-1) -> luci-lib-taskd
find feeds/istore feeds/istore_packages -type f -name "Makefile" -exec sed -i -E 's/\([<=>]+[^)]+\)//g' {} +

# 第二招：彻底消灭 PKG_VERSION 和 PKG_RELEASE 中的连字符 (-)
# 效果：PKG_VERSION:=1.3.0-1 -> PKG_VERSION:=1.3.0.1
find feeds/istore feeds/istore_packages -type f -name "Makefile" -exec sed -i '/^[[:space:]]*PKG_VERSION[[:space:]]*[=:]/ s/-/\./g' {} +
find feeds/istore feeds/istore_packages -type f -name "Makefile" -exec sed -i '/^[[:space:]]*PKG_RELEASE[[:space:]]*[=:]/ s/-/\./g' {} +

# 第三招：智能切除版本号前缀的字母 v 或 V
# 效果：PKG_VERSION:=v1.3.0 -> PKG_VERSION:=1.3.0
find feeds/istore feeds/istore_packages -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*)[vV]([0-9])/\1\2/' {} +

echo "净化完成！"

# 第二步：使用净化后的干净代码进行安装
./scripts/feeds install -d y -p istore luci-app-store
# =================================================================

# 2. 清理默认依赖
echo "清理默认依赖..."
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 3. 拉取 PassWall
echo "拉取 PassWall..."
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages
rm -rf package/pw-luci/shadowsocksr-libev

# 4. 强制 sing-box 同步官方最新版本
echo "正在获取 SagerNet/sing-box 最新版本号..."
SING_BOX_LATEST=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -n "$SING_BOX_LATEST" ] && [ -f "package/pw-luci/sing-box/Makefile" ]; then
    echo "发现 sing-box 官方最新版本: $SING_BOX_LATEST"
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/pw-luci/sing-box/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/pw-luci/sing-box/Makefile
fi

# 5. 修改 IP 地址
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate

# 6. 修复 smartdns 冲突
echo "处理 smartdns 和 luci-app-smartdns..."
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' feeds/packages/net/smartdns/Makefile
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master

# 7. 拉取 Lucky 和 Dockerman
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# 8. 拉取 dae（保留官方兼容的 ZeroTier）
echo "拉取 dae..."
rm -rf package/dae package/luci-app-dae
git clone --depth=1 https://github.com/immortalwrt/packages package/immortalwrt-packages
mv package/immortalwrt-packages/net/dae package/dae
rm -rf package/immortalwrt-packages
sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile

git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci
mv package/immortalwrt-luci/applications/luci-app-dae package/luci-app-dae
rm -rf package/immortalwrt-luci
rm -rf package/luci-app-dae/dae

# 9. 其他组件与 ddns-go 修复
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/yingziwu/openwrt-fakehttp package/openwrt-fakehttp
clone_or_pull https://github.com/yingziwu/luci-app-fakehttp package/luci-app-fakehttp

echo "修复 ddns-go 下载哈希与版本..."
DDNS_GO_LATEST=$(curl -s "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -n "$DDNS_GO_LATEST" ] && [ -f "package/ddns-go/ddns-go/Makefile" ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$DDNS_GO_LATEST/" package/ddns-go/ddns-go/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/ddns-go/ddns-go/Makefile
fi

# 10. 系统优化
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile

# 11. 固件名加前缀和日期
sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g" include/image.mk

# 12. 强制剥离 Transmission 与注入中文配置
echo "清理 Transmission 并在系统层面强制开启中文..."
sed -i '/luci-app-transmission/d' .config || true
sed -i '/luci-i18n-transmission/d' .config || true
sed -i '/transmission-daemon/d' .config || true

echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
echo "CONFIG_LUCI_LANG_zh_cn=y" >> .config

# 13. 系统版本 + 默认语言脚本
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-version <<'EOF'
#!/bin/sh
DATE=$(date +"%Y-%m-%d")
sed -i "s/DISTRIB_DESCRIPTION='.*'/DISTRIB_DESCRIPTION='OpenWrt PVE-N6000 ${DATE}'/g" /etc/openwrt_release
sed -i "s/DISTRIB_REVISION='.*'/DISTRIB_REVISION='R${DATE}'/g" /etc/openwrt_release
uci set luci.main.lang='zh_cn'
uci commit luci
rm -f /etc/uci-defaults/99-custom-version
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-version

echo "=== diyyb1-part2.sh 执行完成 ==="
