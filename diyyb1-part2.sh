#!/bin/bash
# diyyb1-part2.sh (精简审计版)

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

# 1. 清理冲突依赖包
echo "清理默认冲突依赖..."
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 2. 拉取第三方源码
echo "拉取第三方插件..."

# PassWall 1
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/pw-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/pw-luci
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages package/pw-luci/shadowsocksr-libev

# [修改处: 独立拉取 PassWall2，避免与 PW1 依赖冲突]
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall2.git package/pw2-luci

# Lucky & Dockerman
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/luci-app-dockerman

# DAE
rm -rf package/dae package/luci-app-dae
git clone --depth=1 https://github.com/immortalwrt/packages package/immortalwrt-packages
mv package/immortalwrt-packages/net/dae package/dae
rm -rf package/immortalwrt-packages
git clone --depth=1 https://github.com/immortalwrt/luci package/immortalwrt-luci
mv package/immortalwrt-luci/applications/luci-app-dae package/luci-app-dae
rm -rf package/immortalwrt-luci package/luci-app-dae/dae

# DDNS-GO & Geodata & Diskman
clone_or_pull https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
clone_or_pull https://github.com/sirpdboy/luci-app-ddns-go package/ddns-go
clone_or_pull https://github.com/lisaac/luci-app-diskman.git package/luci-app-diskman

# SmartDNS
rm -rf feeds/packages/net/smartdns
clone_or_pull https://github.com/pymumu/openwrt-smartdns.git package/smartdns master
rm -rf package/luci-app-smartdns
clone_or_pull https://github.com/pymumu/luci-app-smartdns.git package/luci-app-smartdns master


# 3. 源码调整与修复
echo "调整与修复第三方源码..."

# [修改处: DAE 路径修复与哈希跳过]
sed -i 's|../../lang/golang/golang-package.mk|$(TOPDIR)/feeds/packages/lang/golang/golang-package.mk|g' package/dae/Makefile
sed -i 's|../../luci.mk|$(TOPDIR)/feeds/luci/luci.mk|g' package/luci-app-dae/Makefile
sed -i 's/PKG_HASH:=.*/PKG_HASH:=skip/g' package/dae/Makefile
sed -i 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=skip/g' package/dae/Makefile

# [修改处: SmartDNS 依赖与路径修复]
sed -i 's|../../lang/rust/rust-package.mk|$(TOPDIR)/feeds/packages/lang/rust/rust-package.mk|g' package/smartdns/Makefile
sed -i 's/DEPENDS:=.*/& +zlib/g' package/smartdns/Makefile


# 4. 净化环境与更新 Feeds
echo "执行包名净化与 Feeds 更新..."
THIRD_PARTY_DIRS="feeds/istore feeds/istore_packages package/pw-luci package/pw2-luci package/lucky package/luci-app-dockerman package/dae package/luci-app-dae package/v2ray-geodata package/ddns-go package/luci-app-diskman package/smartdns package/luci-app-smartdns"

for dir in $THIRD_PARTY_DIRS; do
    if [ -d "$dir" ]; then
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/\([<=>]+[^)]+\)//g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*)[vV]([0-9])/\1\2/g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_VERSION[[:space:]]*:?=[[:space:]]*[0-9\.]+).*/\1/g' {} + || true
        find "$dir" -type f -name "Makefile" -exec sed -i -E 's/^([[:space:]]*PKG_RELEASE[[:space:]]*:?=[[:space:]]*[0-9]+).*/\1/g' {} + || true
    fi
done

rm -rf tmp/
./scripts/feeds update -i
./scripts/feeds install -a
./scripts/feeds install -p istore_packages luci-app-zerotier


# 5. 动态最新版本注入
echo "注入动态最新版本号..."

# Sing-Box
SING_BOX_LATEST=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -n "$SING_BOX_LATEST" ] && [ -f "package/pw-luci/sing-box/Makefile" ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$SING_BOX_LATEST/" package/pw-luci/sing-box/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/pw-luci/sing-box/Makefile
fi

# DDNS-GO
DDNS_GO_LATEST=$(curl -s "https://api.github.com/repos/jeessy2/ddns-go/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -n "$DDNS_GO_LATEST" ] && [ -f "package/ddns-go/ddns-go/Makefile" ]; then
    sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$DDNS_GO_LATEST/" package/ddns-go/ddns-go/Makefile
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=skip/" package/ddns-go/ddns-go/Makefile
fi

# [修改处: DAE 版本注入与 fallback 机制优化]
DAE_LATEST=$(curl -s "https://api.github.com/repos/daeuniverse/dae/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
if [ -z "$DAE_LATEST" ]; then DAE_LATEST="1.1.0"; fi
sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$DAE_LATEST/g" package/dae/Makefile
sed -i "s/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=v$DAE_LATEST/g" package/dae/Makefile

# [修改处: SmartDNS 暴力结构重建，100%匹配最新Tag]
SMARTDNS_LATEST=$(curl -s "https://api.github.com/repos/pymumu/smartdns/releases/latest" | awk -F '"' '/tag_name/{print $4}' | sed 's/^Release//')
if [ -z "$SMARTDNS_LATEST" ]; then SMARTDNS_LATEST="48.1"; fi
if [ -f "package/smartdns/Makefile" ]; then
    sed -i '/PKG_VERSION:=/d' package/smartdns/Makefile
    sed -i '/PKG_SOURCE_VERSION:=/d' package/smartdns/Makefile
    sed -i '/PKG_HASH:=/d' package/smartdns/Makefile
    sed -i '/PKG_MIRROR_HASH:=/d' package/smartdns/Makefile
    sed -i "/PKG_NAME:=.*/a PKG_VERSION:=$SMARTDNS_LATEST\nPKG_SOURCE_VERSION:=Release$SMARTDNS_LATEST\nPKG_HASH:=skip\nPKG_MIRROR_HASH:=skip" package/smartdns/Makefile
fi


# 6. 系统底层配置修改
echo "执行底层剥离与参数调整..."
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$ "' >> package/base-files/files/etc/profile
sed -i "s/IMG_PREFIX:=.*/IMG_PREFIX:=OpenWrt-PVE-N6000-$(date +%Y%m%d)/g" include/image.mk

# 写入中文预设
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-custom-language <<EOF
#!/bin/sh
uci set luci.main.lang='zh_cn'
uci commit luci
rm -f /etc/uci-defaults/99-custom-language
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-custom-language


# 7. 写入 .config 编译标识
echo "注入组件编译配置..."
touch .config

# 剥离多余应用
sed -i '/luci-app-transmission/d' .config
sed -i '/luci-i18n-transmission/d' .config
sed -i '/transmission-daemon/d' .config
sed -i '/luci-app-store/d' .config
sed -i '/luci-i18n-store/d' .config
sed -i '/CONFIG_PACKAGE_luci-app-tailscale/d' .config
sed -i '/CONFIG_PACKAGE_luci-i18n-tailscale/d' .config
sed -i '/CONFIG_PACKAGE_qemu-ga/d' .config

# 基础设置
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> .config
echo "CONFIG_LUCI_LANG_zh_cn=y" >> .config
echo "# CONFIG_PACKAGE_qemu-ga is not set" >> .config

# 镜像版本号
COMPILE_DATE_SHORT="$(date +"%y.%m.%d")"
sed -i '/CONFIG_IMAGEOPT/d' .config
sed -i '/CONFIG_VERSIONOPT/d' .config
sed -i '/CONFIG_VERSION_NUMBER/d' .config
sed -i '/CONFIG_VERSION_CODE/d' .config
echo "CONFIG_IMAGEOPT=y" >> .config
echo "CONFIG_VERSIONOPT=y" >> .config
echo "CONFIG_VERSION_NUMBER=\"R${COMPILE_DATE_SHORT}\"" >> .config
echo "CONFIG_VERSION_CODE=\"\"" >> .config

# 磁盘挂载与文件系统
echo "CONFIG_PACKAGE_block-mount=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
echo "CONFIG_PACKAGE_e2fsprogs=y" >> .config
echo "CONFIG_PACKAGE_blkid=y" >> .config
echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
echo "CONFIG_PACKAGE_ntfs-3g=y" >> .config
echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config

# 协议与代理插件 (PW1, PW2, DAE)
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

echo "CONFIG_PACKAGE_dae=y" >> .config
echo "CONFIG_PACKAGE_luci-app-dae=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-dae-zh-cn=y" >> .config

# [修改处: 移除 PW2 失效的 INCLUDE 标签，追加推荐内核 mihomo]
echo "CONFIG_PACKAGE_luci-app-passwall2=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_mihomo=y" >> .config

# 网络服务插件
echo "CONFIG_PACKAGE_ksmbd-server=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ksmbd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ksmbd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_wsdd2=y" >> .config
echo "CONFIG_PACKAGE_autosamba=y" >> .config
echo "CONFIG_PACKAGE_ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-app-ttyd=y" >> .config
echo "CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y" >> .config
echo "CONFIG_PACKAGE_tailscale=y" >> .config
echo "CONFIG_PACKAGE_kmod-tun=y" >> .config


# 8. 自动挂载与自启服务脚本
echo "注入自启动脚本..."

# 自动挂载
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

# DNS 服务自启接管
cat > package/base-files/files/etc/uci-defaults/99-enable-services <<'EOF'
#!/bin/sh
uci -q set smartdns.@smartdns[0].enabled='1'
uci commit smartdns
/etc/init.d/smartdns enable || true
rm -f /etc/uci-defaults/99-enable-services
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-enable-services


# 9. 内核 BPF 补丁
echo "应用 BPF 内核网络参数..."
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

echo "=== diyyb1-part2.sh 执行完成，构建就绪 ==="
