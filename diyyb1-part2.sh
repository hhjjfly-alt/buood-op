#!/bin/bash
# diyyb1-part2.sh (Master 终极防弹版 - 偏执狂级除雷)

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

# 1. 清理官方冲突依赖包
echo "清理默认冲突依赖..."
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# =================================================================
# 2. 批量拉取所有第三方源码 (全名单无遗漏)
# =================================================================
echo "拉取第三方插件..."

# PassWall
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages package/pw-luci/shadowsocksr-libev

# Lucky & Dockerman
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# ====================================================================
# DAE (锁定编译 v1.1.0 稳定版，避开 2.0.0rc1 编译依赖错误)
# ====================================================================
rm -rf package/dae package/luci-app-dae
git clone --depth=1 https://github.com/immortalwrt/packages package/immortalwrt-packages
mv package/immortalwrt-packages/net/dae package/dae
rm -rf package/immortalwrt-packages
sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile

echo "正在修改 DAE Makefile，强制指定版本为 v1.1.0 ..."
sed -i 's/PKG_VERSION:=.*/PKG_VERSION:=1.1.0/g' package/dae/Makefile
sed -i 's/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=v1.1.0/g' package/dae/Makefile
sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' package/dae/Makefile

git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci
mv package/immortalwrt-luci/applications/luci-app-dae package/luci-app-dae
rm -rf package/immortalwrt-luci package/luci-app-dae/dae

sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' package/luci-app-dae/Makefile
# ====================================================================

# DDNS-GO & Geodata
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go

# Diskman
clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# SmartDNS
echo "处理 smartdns 和 luci-app-smartdns..."
sed -i 's/1.2024.45/1.2025.47/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/0f1912ab020ea9a60efac4732442f0bb7093f40b/g; /^PKG_MIRROR_HASH/s/^/#/' feeds/packages/net/smartdns/Makefile
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master

# HomeProxy 源码直拉
clone_or_pull https://github.com/VIKINGYFY/homeproxy.git package/homeproxy                                   

# 3. 终极 apk 净化 (严格修复正则执行顺序)
# =================================================================
echo "正在对所有第三方包进行强力净化..."

# 净化名单中已彻底移除 fakehttp
THIRD_PARTY_DIRS="feeds/istore feeds/istore_packages package/pw-luci package/lucky package/luci-app-dockerman package/dae package/luci-app-dae package/v2ray-geodata package/ddns-go package/luci-app-diskman package/luci-app-smartdns feeds/momo"

for dir in $THIRD_PARTY_DIRS; do
    if [ -d "$dir" ]; then
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/\([<=>]+[^)]+\)//g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*)[vV]([0-9])/\1\2/g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9\.]+).*/\1/g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*[0-9]+).*/\1/g' {} + || true
    fi
done

echo "净化完成，清空编译系统缓存并重建索引..."
rm -rf tmp/
./scripts/feeds update -i
./scripts/feeds install -a
./scripts/feeds install -p istore_packages luci-app-zerotier

# =================================================================
# 4. 动态最新版注入与系统核心剥离
# =================================================================
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

sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile
sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g" include/image.mk

echo "执行底层剥离与配置注入..."
touch .config

sed -i '/luci-app-transmission/d' .config
sed -i '/luci-i18n-transmission/d' .config
sed -i '/transmission-daemon/d' .config
sed -i '/luci-app-store/d' .config
sed -i '/luci-i18n-store/d' .config

echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
echo "CONFIG_LUCI_LANG_zh_cn=y" >> .config

# =================================================================
# 5. 固件版本号与真实编译日期注入
# =================================================================
COMPILE_DATE_SHORT="$(date +"%y.%m.%d")"
touch .config
sed -i '/CONFIG_IMAGEOPT/d' .config
sed -i '/CONFIG_VERSIONOPT/d' .config
sed -i '/CONFIG_VERSION_NUMBER/d' .config
sed -i '/CONFIG_VERSION_CODE/d' .config

echo "CONFIG_IMAGEOPT=y" >> .config
echo "CONFIG_VERSIONOPT=y" >> .config
echo "CONFIG_VERSION_NUMBER=\"R${COMPILE_DATE_SHORT}\"" >> .config
echo "CONFIG_VERSION_CODE=\"\"" >> .config

# 强制中文
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-language <<EOF
#!/bin/sh
uci set luci.main.lang='zh_cn'
uci commit luci
rm -f /etc/uci-defaults/99-custom-language
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-language

# =================================================================
# 6. 强制编译磁盘挂载核心组件
# =================================================================
echo "CONFIG_PACKAGE_block-mount=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
echo "CONFIG_PACKAGE_e2fsprogs=y" >> .config
echo "CONFIG_PACKAGE_blkid=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
echo "CONFIG_PACKAGE_ntfs-3g=y" >> .config
echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config

cat > package/base-files/files/etc/uci-defaults/99-auto-mount <<'EOF'
#!/bin/sh
uci -q delete fstab.sda3
uci set fstab.sda3="mount"
uci set fstab.sda3.device="/dev/sda3"
uci set fstab.sda3.target="/mnt/sda3"
uci set fstab.sda3.fstype="ext4"
uci set fstab.sda3.options="rw,relatime"
uci set fstab.sda3.enabled="1"
uci commit fstab
/etc/init.d/fstab enable
block mount
[ -x /etc/init.d/dockerd ] && /etc/init.d/dockerd restart || true
rm -f /etc/uci-defaults/99-auto-mount
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-auto-mount

# =================================================================
# 7. 协议核心唤醒及各项组件
# =================================================================
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria=y" >> .config
echo "CONFIG_PACKAGE_hysteria=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox=y" >> .config
echo "CONFIG_PACKAGE_sing-box=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y" >> .config
echo "CONFIG_PACKAGE_xray-core=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Go=y" >> .config
echo "CONFIG_PACKAGE_trojan-go=y" >> .config
echo "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Plus=y" >> .config
echo "CONFIG_PACKAGE_trojan-plus=y" >> .config

echo "CONFIG_PACKAGE_momo=y" >> .config
echo "CONFIG_PACKAGE_luci-app-momo=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-momo-zh-cn=y" >> .config 

echo "CONFIG_PACKAGE_homeproxy=y" >> .config
echo "CONFIG_PACKAGE_luci-app-homeproxy=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn=y" >> .config

echo "CONFIG_PACKAGE_ksmbd-server=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ksmbd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_wsdd2=y" >> .config
echo "CONFIG_PACKAGE_autosamba=y" >> .config

echo "CONFIG_PACKAGE_ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y" >> .config

# === 核心修改：强制 PassWall 和 SmartDNS 开启并设为自动启动 ===
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-enable-services <<'EOF'
#!/bin/sh
# 强制开启 PassWall
uci -q set passwall.main.enabled='1'
uci commit passwall
/etc/init.d/passwall enable || true

# 强制开启 SmartDNS
uci -q set smartdns.@smartdns[0].enabled='1'
uci commit smartdns
/etc/init.d/smartdns enable || true

rm -f /etc/uci-defaults/99-enable-services
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-enable-services
# ==============================================================

# ==================== 针对 6.18 内核环境的底层排雷与修复 ====================
for conf in target/linux/generic/config-*; do
    echo "CONFIG_NET_SCH_BPF=y" >> "$conf"
    echo "CONFIG_NET_ACT_BPF=y" >> "$conf"
    echo "CONFIG_NET_CLS_BPF=y" >> "$conf"
done
for conf in target/linux/x86/config-*; do
    echo "CONFIG_NET_SCH_BPF=y" >> "$conf"
    echo "CONFIG_NET_ACT_BPF=y" >> "$conf"
    echo "CONFIG_NET_CLS_BPF=y" >> "$conf"
done

sed -i '/CONFIG_PACKAGE_qemu-ga/d' .config
echo "# CONFIG_PACKAGE_qemu-ga is not set" >> .config
# =========================================================================

echo "=== diyyb1-part2.sh 执行完成，零警告护航模式就绪 ==="
