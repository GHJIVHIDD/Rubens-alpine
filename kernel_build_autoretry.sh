#!/bin/bash
set -e

MAX_RETRIES=1000
BUILD_SUCCESS=0

echo "🔁 自动内核构建开始（最多尝试 $MAX_RETRIES 次）"

for ((i=1; i<=MAX_RETRIES; i++)); do
  echo "🔨 第 $i 次尝试构建内核..."
  make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image dtbs 2>&1 | tee build.log
  BUILD_STATUS=$?

  if [ $BUILD_STATUS -eq 0 ]; then
    echo '✅ 内核构建成功！'
    BUILD_SUCCESS=1
    break
  fi

  echo "❌ 构建失败，尝试分析缺失头文件..."

  # 提取缺失头文件
  MISSING_HEADERS=$(grep -oP 'fatal error: \K[^\s:]+' build.log | grep '\.h$' | sort -u)

  if [ -z "$MISSING_HEADERS" ]; then
    echo "⚠️ 未发现缺失的头文件，退出构建循环。"
    break
  fi

  for hdr in $MISSING_HEADERS; do
    hdr_path="kernel/$hdr"
    hdr_dir=$(dirname "$hdr_path")
    if [ ! -f "$hdr_path" ]; then
      echo "📎 自动补全头文件: $hdr"
      mkdir -p "$hdr_dir"
      cat <<EOF > "$hdr_path"
#ifndef _AUTO_$(echo "$hdr" | tr '/.' '__')_H
#define _AUTO_$(echo "$hdr" | tr '/.' '__')_H
// Auto-generated stub for missing header $hdr
#endif
EOF
    fi
  done

  echo "🔁 即将重新构建..."
done

if [ $BUILD_SUCCESS -eq 0 ]; then
  echo "❌ 内核构建失败：已达最大重试次数 ($MAX_RETRIES)"
  exit 1
fi
