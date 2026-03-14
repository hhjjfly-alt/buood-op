#!/bin/bash
# diyyb1-part2.sh (Master 终极防崩溃装甲版)

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

# 1. 净化官方源自带的依赖（清理冲突）
echo "清理默认依赖..."
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# =================================================================
# 2. 批量拉取所有第三方源码（确保不遗漏任何一个你需要的菜单）
# =================================================================
echo "拉取第三方源码..."
# PassWall
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages
rm -rf package/pw-luci/shadowsocksr-libev

# Lucky & Dockerman
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# DAE
rm -rf package/dae package/luci-app-dae
git clone --depth=1 https://github.com/immortalwrt/packages package/immortalwrt-packages
mv package/immortalwrt-packages/net/dae package/dae
rm -rf package/immortalwrt-packages
sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile

git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci
mv package/immortalwrt-luci/applications/luci-app-dae package/luci-app-dae
rm -rf package/immortalwrt-luci
rm -rf package/luci-app-dae/dae

# DDNS-GO, Fakehttp & Geodata
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/yingziwu/openwrt-fakehttp package/openwrt-fakehttp
clone_or_pull https://github.com/yingziwu/luci-app-fakehttp package/luci-app-fakehttp

# AdGuardHome 和 Diskman
clone_or_pull https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome
clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# SmartDNS
echo "处理 smartdns 和 luci-app-smartdns..."
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' feeds/packages/net/smartdns/Makefile
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master


# =================================================================
# 3. 终极兼容性净化手术：强行合规化所有第三方包！
# =================================================================
echo "正在净化所有第三方 package 的版本号..."

# 包括了 iStore 的 feeds 目录以及所有我们手动 clone 的目录
THIRD_PARTY_DIRS="feeds/istore feeds/istore_packages package/pw-luci package/lucky package/luci-app-dockerman package/dae package/luci-app-dae package/v2ray-geodata package/ddns-go package/openwrt-fakehttp package/luci-app-fakehttp package/luci-app-smartdns package/luci-app-adguardhome package/luci-app-diskman"

for dir in $THIRD_PARTY_DIRS; do
    if [ -d "$dir" ]; then
        # 1. 彻底摧毁带符号的依赖限制 (解决菜单不显示)
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/\([<=>]+[^)]+\)//g' {} + || true
        
        # 2. 【升级版安全截断】只保留版本号里的纯数字和点，彻底砍掉连字符和后面的内容 (解决 apk 崩溃)
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9\.]+).*/\1/g' {} + || true
        
        # 3. 将 PKG_RELEASE 也进行严格的截断，只保留第一串数字
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*[0-9]+).*/\1/g' {} + || true
        
        # 4. 去除版本号最前面的字母 v 或 V
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*)[vV]([0-9])/\1\2/g' {} + || true
    fi
done

echo "净化完成，正在强制刷新系统索引缓存..."
# 【极其重要】强迫 OpenWrt 系统重新读取刚才被我们改过的 Makefile，确保旧索引被覆盖！
./scripts/feeds update -i
./scripts/feeds install -a


# =================================================================
# 4. 其他系统优化与动态配置
# =================================================================
# 强制 sing-box 和 ddns-go 同步官方最新版本 (绕过 Hash 检查)
SING_BOX_LATEST=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -n "$SING_BOX_LATEST" ] && [ -f "package/pw-luci/sing-box/Makefile" ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/pw-luci/sing-box/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/pw-luci/sing-box/Makefile
fi
DDNS_GO_LATEST=$(curl -s "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -n "$DDNS_GO_LATEST" ] && [ -f "package/ddns-go/ddns-go/Makefile" ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$DDNS_GO_LATEST/" package/ddns-go/ddns-go/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/ddns-go/ddns-go/Makefile
fi

# 系统底层参数优化
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile
sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g" include/image.mk

# 剥离不兼容项与强制开启中文
echo "剥离不支持的组件并开启中文..."
sed -i '/luci-app-transmission/d' .config || true
sed -i '/luci-i18n-transmission/d' .config || true
sed -i '/transmission-daemon/d' .config || true

# 强行删除 iStore，避免因 apk 不兼容导致产生空壳
sed -i '/luci-app-store/d' .config || true
sed -i '/luci-i18n-store/d' .config || true

echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
echo "CONFIG_LUCI_LANG_zh_cn=y" >> .config

# 系统版本信息注入
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
