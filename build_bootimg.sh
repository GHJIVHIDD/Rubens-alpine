#!/bin/bash
set -e

echo "📦 下载 Linux 5.10.209 主线源码..."
wget -q https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.10.209.tar.xz
tar -xf linux-5.10.209.tar.xz
mv linux-5.10.209 kernel

echo "📂 合并 rubens 驱动中..."
if [ -d "drivers" ]; then
  cp -r drivers/* kernel/drivers/ || true
fi
if [ -d "arch" ]; then
  cp -r arch/* kernel/arch/ || true
fi

echo "⚙️ 复制 .config..."
cp .config kernel/.config

cd kernel

echo '🩹 自动补全缺失头文件 wakeup_reason.h...'
mkdir -p include/linux
cat > include/linux/wakeup_reason.h <<EOF
#ifndef _LINUX_WAKEUP_REASON_H
#define _LINUX_WAKEUP_REASON_H

// Stub implementation for wakeup_reason.h
// This is safe for build but doesn't do actual wakeup reason logging

static inline void log_wakeup_reason(int irq) {}
static inline void enable_irq_wake_logging(int enable) {}

#endif // _LINUX_WAKEUP_REASON_H
EOF
echo '✅ include/linux/wakeup_reason.h 已补全'

echo '🩹 自动补全缺失头文件 trace/hooks/gic_v3.h...'
mkdir -p kernel/trace/hooks
cat > kernel/trace/hooks/gic_v3.h <<EOF
#ifndef _TRACE_HOOK_GIC_V3_H
#define _TRACE_HOOK_GIC_V3_H

// Stub for missing gic_v3.h trace hook
// Allows build to continue, but tracing will not function

#endif
EOF
echo '✅ trace/hooks/gic_v3.h 已补全'
make ARCH=arm64 olddefconfig
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image dtbs
cd ..

echo "🧵 构建 initramfs..."
mkdir -p initramfs/{bin,sbin,etc,proc,sys,usr/bin,usr/sbin,dev}
cp init initramfs/init
chmod +x initramfs/init
(cd initramfs && find . | cpio -o --format=newc | gzip > ../ramdisk.cpio.gz)

echo "📦 构建 boot.img..."
DTB=$(find kernel/arch/arm64/boot/dts/mediatek -name '*.dtb' | head -n1)
if ! command -v mkbootimg >/dev/null; then
  echo "❌ mkbootimg 未安装或不可用，请确保平台支持。"
  exit 1
fi
mkbootimg --kernel kernel/arch/arm64/boot/Image --dtb "$DTB" --ramdisk ramdisk.cpio.gz \
  --base 0x00000000 --pagesize 4096 --cmdline 'console=ttyS0 root=/dev/ram0 init=/init rw' -o boot.img

echo '🔍 检查构建过程中所有缺失的头文件引用...'
grep -r --include='*.c' --include='*.h' '#include <' . | \
  grep -v '"' | \
  sed -n 's/.*#include <\(.*\)>/\1/p' | sort -u | \
  while read hdr; do
    if ! find . -type f -name "$(basename $hdr)" | grep -q .; then
      echo "❌ 缺失头文件: <$hdr>"
    fi
  done
