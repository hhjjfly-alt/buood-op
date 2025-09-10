#!/bin/bash
#  diy-part2.sh  （After Update feeds）
#  功能清单：
#  1. 万能克隆函数
#  2. 最新 PassWall（覆盖 feeds 目录，避免双份）
#  3. 默认 IP / 主机名 / 固件名 / 系统版本加日期
#  4. SmartDNS 自动 bump 最新 tag+hash（同步 luci）
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

########### 0. 若 istore 已存在则跳过（避免重复） ###########
grep -q '^src-git istore' feeds.conf.default || {
  echo 'src-git istore https://github.com/linkease/istore ;main' >> feeds.conf.default
  ./scripts/feeds update istore
  ./scripts/feeds install -d y -p istore luci-app-store
}

########### 1. 最新 PassWall（仅覆盖 feeds 目录，不动 package） ###########
# 1.1 删除可能存在的 package/ 副本（防止双份）
rm -rf package/pw-packages package/pw-luci

# 1.2 强制刷新 feeds 目录（利用 part1 已添加的 feed）
./scripts/feeds update passwall_packages passwall_luci
./scripts/feeds install -a -p passwall_packages
./scripts/feeds install -a -p passwall_luci

# 1.3 修复 geoview 二次编译 protobuf 缓存缺失
geoview_mk="feeds/passwall_packages/geoview/Makefile"
[[ -f "$geoview_mk" ]] && {
  sed -i '/^GO_MOD_DOWNLOAD_ARGS.*GO_MOD_CACHE_DIR/d' "$geoview_mk"
  echo "=== 已修补 $geoview_mk ，geoview 不再复用残缺缓存 ==="
}

########### 2. 默认 IP / 主机名 / 固件名 / 系统版本 ###########
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk
zzz=$(find package/ -type f -name zzz-default-settings | grep -E 'lean|default-settings' | head -n1)
[[ -n $zzz ]] && {
  echo "=== 找到 $zzz ，追加日期 ==="
  sed -i '/http/d' "$zzz"
  orig=$(grep DISTRIB_REVISION= "$zzz" | awk -F"'" '{print $2}')
  sed -i "s/${orig}/${orig} ($(date +%Y-%m-%d))/g" "$zzz"
}

########### 3. SmartDNS 自动 bump 最新 tag+hash（同步 luci） ###########
PKGS_MK=feeds/packages/net/smartdns/Makefile
LUCI_MK=feeds/smartdns_luci/luci-app-smartdns/Makefile
if [[ -f $PKGS_MK && -f $LUCI_MK ]]; then
  LATEST_TAG=$(curl -s https://api.github.com/repos/pymumu/smartdns/tags | jq -r '.[0].name')
  LATEST_HASH=$(curl -s https://api.github.com/repos/pymumu/smartdns/commits?per_page=1 | jq -r '.[0].sha[0:7]')
  if [[ -n "$LATEST_TAG" && -n "$LATEST_HASH" ]]; then
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$LATEST_TAG/"           "$PKGS_MK"
    sed -i "s/PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$LATEST_HASH/" "$PKGS_MK"
    sed -i '/PKG_MIRROR_HASH/d'                                   "$PKGS_MK"
    # 同步 luci 版本号，避免 hash 不一致
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$LATEST_TAG/"           "$LUCI_MK"
    echo "=== SmartDNS 已 bump 到 $LATEST_TAG ($LATEST_HASH) ==="
  else
    echo "=== 获取 SmartDNS 最新版本失败，保持原样 ==="
  fi
fi

########### 4. 额外插件（lucky & dockerman）幂等克隆 ###########
clone_or_pull https://github.com/gdy666/luci-app-lucky.git    package/lucky
pushd package/lean
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git   luci-app-dockerman
popd

########### 5. 系统调优 ###########
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile

########### 6. 官方最新 sing-box（仅 OpenWrt 部分） ###########
rm -rf package/sing-box
SINGBOX_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tarball_url')
mkdir -p package/sing-box
curl -L "$SINGBOX_URL" | tar -xz -C package/sing-box --strip=1
# 拷贝官方 Makefile（若 feeds 已 install 过则必存在）
cp feeds/packages/net/sing-box/Makefile package/sing-box/ 2>/dev/null || \
  echo "=== 未找到 feeds 里的 sing-box Makefile，请手动处理 ==="
