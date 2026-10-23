#!/bin/sh
# Build OpenWrt dumb-AP cho Xiaomi CR8806. Chay tu thu muc goc cua source.
set -e
cd "$(dirname "$0")/.."
./scripts/feeds update -a
./scripts/feeds install -a
rm -rf files && cp -a cr8806/files files
cp cr8806/diffconfig .config
make defconfig
# Module ngoai cay kernel (ath11k smallbuffers...) khong tu build lai khi cau
# hinh kernel doi -> WiFi hong. Luon build lai chung.
make package/kernel/mac80211/clean package/kernel/gpio-button-hotplug/clean
make -j"$(nproc)" download
make -j"$(nproc)" || make -j1 V=s
ls -l bin/targets/qualcommax/ipq50xx/*cr8806*
