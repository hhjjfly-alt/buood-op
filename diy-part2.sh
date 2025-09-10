#!/bin/bash
#  diy-part2.sh  （After Update feeds）
#  功能清单：
#  1. 万能克隆函数
#  2. 最新 PassWall（删-拉-覆盖法）→ 永远官方 HEAD
#  3. 默认 IP / 主机名 / 固件名 / 系统版本加日期
#  4. SmartDNS 自动 bump 最新 tag+hash
#  5. 额外插件（lucky & dockerman）幂等克隆
#  6. 连接数优化 & 其它系统调优
#  7. 官方最新 sing-box（仅 OpenWrt 部分）
########### 万能函数：克隆或拉取最新 ###########
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

########### 0. 提前追加 istore 源（保证第一次 feeds update 就可用） ###########
grep -q '^src-git istore' feeds.conf.default ||
  echo 'src-git istore https://github.com/linkease/istore ;main' >> feeds.conf.default
./scripts/feeds update istore
./scripts/feeds install -d y -p istore luci-app-store

########### 1. 最新 PassWall（删-拉-覆盖法） ###########
# 1.1 删光 lean 老包（确保官方包优先级最高）
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall

# 1.2 拉官方仓库 → package/ 目录（HEAD 即最新）
clone_or_pull https://github.com/xiaorouji/openwrt-passwall-packages.git    package/pw-packages
clone_or_pull https://github.com/xiaorouji/openwrt-passwall.git                 package/pw-luci

# 1.3 二进制包全部塞进 luci 目录，用完即扔
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages

# 1.4 强制重新下载源码（保证每次编译都是最新 commit）
rm -rf feeds/chinadns_ng/* feeds/passwall_packages/* feeds/passwall_luci/*

########### 1.5 修复 geoview 二次编译 protobuf 缓存缺失 ###########
geoview_mk="package/pw-luci/geoview/Makefile"
if [ -f "$geoview_mk" ]; then
  sed -i '/^GO_MOD_DOWNLOAD_ARGS.*GO_MOD_CACHE_DIR/d' "$geoview_mk"
  echo "=== 已修补 $geoview_mk ，geoview 不再复用残缺缓存 ==="
fi

########### 2. 默认 IP / 主机名 / 固件名 / 系统版本 ###########
# 2.1 默认 IP
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate

# 2.2 固件名加日期
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk

# 2.3 系统版本加日期（仅 lean 的 default-settings）
zzz=$(find package/ -type f -name zzz-default-settings | grep -E 'lean|default-settings' | head -n1)
if [ -n "$zzz" ]; then
  echo "=== 找到 $zzz ，追加日期 ==="
  sed -i '/http/d' "$zzz"
  orig=$(grep DISTRIB_REVISION= "$zzz" | awk -F"'" '{print $2}')
  sed -i "s/${orig}/${orig} ($(date +%Y-%m-%d))/g" "$zzz"
else
  echo "=== lean/default-settings 未找到，跳过版本加日期 ==="
fi

########### 3. SmartDNS 自动 bump 最新 tag+hash ###########
SMARTDNS_MK=feeds/packages/net/smartdns/Makefile
# 取最新 tag 与对应 commit hash
LATEST_TAG=$(curl -s https://api.github.com/repos/pymumu/smartdns/tags | jq -r '.[0].name')
LATEST_HASH=$(curl -s https://api.github.com/repos/pymumu/smartdns/commits?per_page=1 | jq -r '.[0].sha[0:7]')
if [ -n "$LATEST_TAG" ] && [ -n "$LATEST_HASH" ]; then
  sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$LATEST_TAG/"           "$SMARTDNS_MK"
  sed -i "s/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$LATEST_HASH/" "$SMARTDNS_MK"
  sed -i '/PKG_MIRROR_HASH/d'                                   "$SMARTDNS_MK"
  echo "=== SmartDNS 已 bump 到 $LATEST_TAG ($LATEST_HASH) ==="
else
  echo "=== 获取 SmartDNS 最新版本失败，保持原样 ==="
fi

########### 4. 额外插件（幂等克隆） ###########
clone_or_pull https://github.com/gdy666/luci-app-lucky.git    package/lucky
pushd package/lean
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git   luci-app-dockerman
popd

########### 5. 系统调优 ###########
# 5.1 连接数上限
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
# 5.2 默认 shell 提示符颜色（可选）
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile

########### 6. 官方最新 sing-box（仅 OpenWrt 部分） ###########
# 6.1 删除旧包
rm -rf feeds/packages/net/sing-box package/sing-box
# 6.2 拉取官方最新 release 源码（仅 Linux 部分，无安卓/Windows）
SINGBOX_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tarball_url')
mkdir -p package/sing-box
curl -L "$SINGBOX_URL" | tar -xz -C package/sing-box --strip=1
# 6.3 把官方 Makefile 拷进来（OpenWrt 官方仓库自带）
cp feeds/packages/net/sing-box/Makefile package/sing-box/ 2>/dev/null || \
  echo "=== 未找到 feeds 里的 sing-box Makefile，请手动处理 ==="
