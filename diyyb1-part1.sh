#!/bin/bash
# diyyb1-part1.sh
# 仅预留扩展位。zerotier 使用 OpenWrt 官方 feeds，不再引入 istore 旧包。
set -e

# 若以后需要自定义 feed，按下面格式追加：
# add_feed() {
#     local name=$1 url=$2
#     if ! grep -q "^src-git $name " feeds.conf.default; then
#         echo "src-git $name $url" >> feeds.conf.default
#     fi
# }
# add_feed example 'https://github.com/example/repo;main'

echo "=== diyyb1-part1.sh：无额外 feed（使用官方 zerotier） ==="
exit 0
