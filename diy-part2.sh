#!/bin/bash
#  diy-part2.sh  （After Update feeds）
#  功能清单：
#  1. 万能克隆函数
#  2. 最新 PassWall（删-拉-覆盖法）→ 永远官方 HEAD
#  3. 默认 IP / 主机名 / 固件名 / 系统版本加日期
#  4. SmartDNS 版本 bump
#  5. 额外插件（lucky & dockerman）幂等克隆
#  6. 连接数优化 & 其它系统调优
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
  echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
  ./scripts/feeds update istore
  ./scripts/feeds install -d y -p istore luci-app-store
}
########### 1. 最新 PassWall（删-拉-覆盖法） ###########
# 1.1 删光 lean 老包（确保官方包优先级最高）
rm -rf feeds/luci/applications/luci-app-passwall

# 1.2 拉官方仓库 → package/ 目录（HEAD 即最新）
clone_or_pull https://github.com/xiaorouji/openwrt-passwall-packages.git  package/pw-packages
clone_or_pull https://github.com/xiaorouji/openwrt-passwall.git               package/pw-luci

# 1.3 二进制包全部塞进 luci 目录，用完即扔
cp -rf package/pw-packages/* package/pw-luci/
rm -rf package/pw-packages

# ==================== 在这里粘贴新的修复代码 ====================
# 通用化自动修复：为所有 Go 软件包的 Makefile 添加 GO_MOD_TIDY:=1
echo "Patching ALL Go package Makefiles with GO_MOD_TIDY..."

# 使用 find 命令查找 pw-luci 目录下所有的 Makefile 文件
find package/pw-luci -name 'Makefile' | while read -r makefile_path; do
    # 检查 Makefile 是否属于一个 Go 软件包 (通过是否包含 golang-package.mk 来判断)
    if grep -q 'golang-package.mk' "$makefile_path"; then
        # 检查是否已添加过补丁，避免重复
        if ! grep -q "GO_MOD_TIDY:=1" "$makefile_path"; then
            # 在包含 golang-package.mk 的那一行下面，追加 GO_MOD_TIDY:=1
            sed -i '/golang-package.mk/a GO_MOD_TIDY:=1' "$makefile_path"
            echo "  -> Patched Go Makefile: ${makefile_path}"
        fi
    fi
done
# =============================================================

# 1.4 强制重新下载源码（保证每次编译都是最新 commit）
rm -rf feeds/chinadns_ng/* feeds/passwall_packages/* feeds/passwall_luci/*

########### 6. 编译官方最新 sing-box（主仓 + 子模块） ###########
########### 6. 仅拉取 OpenWrt 部分（跳过移动端子模块） ###########
# 6.1 删除旧包
rm -rf feeds/packages/net/sing-box package/sing-box

########### 2. 默认 IP / 主机名 / 固件名 / 系统版本 ###########
# 2.1 默认 IP
sed -i 's/192.168.1.1/10.0.0.10/g' package/base-files/files/bin/config_generate

# 2.2 固件名加日期
sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk

# 2.3 系统版本加日期（保留原描述）
pushd package/lean/default-settings/files
sed -i '/http/d' zzz-default-settings

# 给 DISTRIB_REVISION 加日期
orig_version="$(grep DISTRIB_REVISION= zzz-default-settings | awk -F"'" '{print $2}')"
sed -i "s/${orig_version}/${orig_version} ($(date +%Y-%m-%d))/g" zzz-default-settings

# 在 DISTRIB_DESCRIPTION 末尾追加日期
# sed -i "s/\(DISTRIB_DESCRIPTION=.*\)'/\1 ($(date +%Y%m%d))'/" zzz-default-settings
popd

########### 3. SmartDNS 版本 bump（可选） ###########
sed -i 's/1\.2024\.45/1.2024.46/g; s/9ee27e7ba2d9789b7e007410e76c06a957f85e98/b525170bfd627607ee5ac81f97ae0f1f4f087d6b/g; /^PKG_MIRROR_HASH/s/^/#/' \
       feeds/packages/net/smartdns/Makefile

########### 4. 额外插件（幂等克隆） ###########
clone_or_pull https://github.com/gdy666/luci-app-lucky.git  package/lucky
pushd package/lean
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git luci-app-dockerman
popd

########### 5. 系统调优 ###########
# 5.1 连接数上限
mkdir -p package/base-files/files/etc
echo 'net.netfilter.nf_conntrack_max=165535' >> package/base-files/files/etc/sysctl.conf
# 5.2 默认 shell 提示符颜色（可选）
echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> package/base-files/files/etc/profile

########### 6. 其它可选微调（按需打开） ###########
# 6.1 关闭无用服务
# sed -i '/dnsmasq/d' include/target.mk
# 6.2 默认开启 WiFi（无无线可忽略）
# sed -i 's/disabled=1/disabled=0/g' package/kernel/mac80211/files/lib/wifi/mac80211.sh
