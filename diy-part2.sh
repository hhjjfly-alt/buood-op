#!/bin/bash
# diy-part2.sh  （After Update feeds）
# 针对 coolsnowwolf/lede 最终加固版
# Docker 修复对齐 openwrt/packages PR #30288（已对 docker-v29.6.1 验证）
set -eo pipefail
########### 万能函数：克隆或拉取最新 ###########
clone_or_pull() {
  local repo="$1"
  local dir="$2"
  local branch="${3:-}"
  if [[ -d "$dir/.git" ]]; then
    echo ">>> Update $dir ..."
    git -C "$dir" remote set-url origin "$repo" 2>/dev/null || true
    if [[ -n "$branch" ]]; then
      git -C "$dir" fetch --depth 1 origin "$branch"
      git -C "$dir" checkout -B "$branch" "origin/$branch" 2>/dev/null || \
        git -C "$dir" reset --hard "origin/$branch"
    else
      git -C "$dir" fetch --depth 1 origin
      local target
      target=$(git -C "$dir" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || true
      if [[ -n "$target" ]]; then
        git -C "$dir" reset --hard "origin/$target"
      else
        git -C "$dir" reset --hard FETCH_HEAD
      fi
    fi
  else
    echo ">>> Clone $repo -> $dir ..."
    if [[ -n "$branch" ]]; then
      git clone --depth 1 -b "$branch" "$repo" "$dir"
    else
      git clone --depth 1 "$repo" "$dir"
    fi
  fi
}
append_if_missing() {
  local line="$1"
  local file="$2"
  mkdir -p "$(dirname "$file")"
  grep -qxF "$line" "$file" 2>/dev/null || echo "$line" >> "$file"
}
########### 0. istore ###########
if ! grep -qE '^src-git[[:space:]]+istore[[:space:]]' feeds.conf.default 2>/dev/null; then
  echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
  ./scripts/feeds update istore
  ./scripts/feeds install -d y -p istore luci-app-store
fi
########### 1. PassWall ###########
rm -rf feeds/packages/net/{chinadns-ng,dns2socks,geoview,hysteria,ipt2socks,microsocks,naiveproxy,shadow-tls,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,sing-box,tcping,trojan-plus,tuic-client,v2ray-core,v2ray-geodata,v2ray-plugin,xray-core,xray-plugin}
rm -rf feeds/luci/applications/luci-app-passwall
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
clone_or_pull https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci
########### 2. 默认 IP / 固件名 / 系统版本 ###########
if [[ -f package/base-files/files/bin/config_generate ]]; then
  sed -i 's/192\.168\.1\.1/10.0.0.10/g' package/base-files/files/bin/config_generate
fi
if [[ -f include/image.mk ]]; then
  sed -i 's/IMG_PREFIX:=.*/IMG_PREFIX:=full-$(shell date +%Y%m%d)-$(VERSION_DIST_SANITIZED)/g' include/image.mk
fi
if [[ -f package/lean/default-settings/files/zzz-default-settings ]]; then
  pushd package/lean/default-settings/files >/dev/null
  sed -i '/http/d' zzz-default-settings 2>/dev/null || true
  if grep -q "DISTRIB_REVISION=" zzz-default-settings; then
    orig_version="$(grep "DISTRIB_REVISION=" zzz-default-settings | awk -F"'" '{print $2}')"
    if [[ -n "$orig_version" ]] && ! echo "$orig_version" | grep -qE '\([0-9]{4}-[0-9]{2}-[0-9]{2}\)'; then
      sed -i "s/${orig_version}/${orig_version} ($(date +%Y-%m-%d))/g" zzz-default-settings
    fi
  fi
  popd >/dev/null
fi
########### 3. SmartDNS ###########
SMARTDNS_MK="feeds/packages/net/smartdns/Makefile"
if [[ -f "$SMARTDNS_MK" ]]; then
  echo ">>> Bumping SmartDNS (hash check skipped)"
  sed -i -E 's/^PKG_VERSION:=.*/PKG_VERSION:=1.2025.47/' "$SMARTDNS_MK"
  sed -i -E 's/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=0f1912ab020ea9a60efac4732442f0bb7093f40b/' "$SMARTDNS_MK"
  sed -i -E 's/^PKG_MIRROR_HASH:=.*/# &/' "$SMARTDNS_MK"
  sed -i -E 's/^PKG_HASH:=.*/PKG_HASH:=skip/' "$SMARTDNS_MK"
fi
########### 4. 额外插件 ###########
clone_or_pull https://github.com/gdy666/luci-app-lucky.git package/lucky
mkdir -p package/lean
clone_or_pull https://github.com/lisaac/luci-app-dockerman.git package/lean/luci-app-dockerman
########### 5. 系统调优 ###########
mkdir -p package/base-files/files/etc
append_if_missing 'net.netfilter.nf_conntrack_max=165535' package/base-files/files/etc/sysctl.conf
PROFILE="package/base-files/files/etc/profile"
mkdir -p "$(dirname "$PROFILE")"
if ! grep -q 'PS1=.*\\u@\\h' "$PROFILE" 2>/dev/null; then
  echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> "$PROFILE"
fi
########### 6. dockerd 修复（PR #30288 官方补丁，已验证） ###########
DOCKERD_DIR=""
for candidate in \
  feeds/packages/utils/dockerd \
  package/feeds/packages/utils/dockerd
do
  if [[ -f "$candidate/Makefile" ]]; then
    DOCKERD_DIR="$candidate"
    break
  fi
done
if [[ -n "$DOCKERD_DIR" ]]; then
  PATCH_DIR="$DOCKERD_DIR/patches"
  mkdir -p "$PATCH_DIR"
  PATCH_FILE="$PATCH_DIR/001-skip-copy-nested-binaries.patch"
  cat > "$PATCH_FILE" << 'PATCH_EOF'
From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001
From: Andy Chiang <AndyChiang_git@outlook.com>
Date: Sun, 16 Aug 2026 22:50:48 +0700
Subject: [PATCH] skip copy nested binaries

This script copies containerd, containerd-shim-runc-v2, ctr, runc,
docker-init, rootlesskit, dockerd-rootless.sh, and dockerd-rootless-setuptool.sh
into the `$dir` directory, which is unnecessary for OpenWrt. Moreover,
if the host is missing any one of these files, cp will fail and cause an error.

Fixes:
Copying nested executables into bundles/binary-daemon
cp: cannot stat '': No such file or directory
make[3]: *** [Makefile:166: /home/runner/work/Build/Build/openwrt/build_dir/target-x86_64_musl/dockerd-29.6.1/.built] Error 1

Signed-off-by: Andy Chiang <AndyChiang_git@outlook.com>
---
 hack/make/binary-daemon | 16 +---------------
 1 file changed, 1 insertion(+), 15 deletions(-)

--- a/hack/make/binary-daemon
+++ b/hack/make/binary-daemon
@@ -2,21 +2,7 @@
 set -e
 
 copy_binaries() {
-	local dir="${1:?}"
-
-	# Add nested executables to bundle dir so we have complete set of
-	# them available, but only if the native OS/ARCH is the same as the
-	# OS/ARCH of the build target
-	if [ "$(go env GOOS)/$(go env GOARCH)" != "$(go env GOHOSTOS)/$(go env GOHOSTARCH)" ]; then
-		return
-	fi
-	if [ ! -x /usr/local/bin/runc ]; then
-		return
-	fi
-	echo "Copying nested executables into $dir"
-	for file in containerd containerd-shim-runc-v2 ctr runc docker-init rootlesskit dockerd-rootless.sh dockerd-rootless-setuptool.sh; do
-		cp -f "$(command -v "$file")" "$dir/"
-	done
+	return
 }
 
 [ -z "$KEEPDEST" ] && rm -rf "$DEST"
PATCH_EOF
  echo ">>> Applied dockerd skip-copy-nested-binaries patch to $DOCKERD_DIR"
else
  echo ">>> WARNING: dockerd Makefile not found, skip patch"
fi
