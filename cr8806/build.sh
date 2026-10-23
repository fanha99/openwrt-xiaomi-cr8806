#!/bin/sh
# Build OpenWrt cho Xiaomi CR8806. Chay tu bat ky dau.
#   ./cr8806/build.sh            -> build ca 2 ban: ap roi router
#   ./cr8806/build.sh ap         -> chi ban dumb AP
#   ./cr8806/build.sh router     -> chi ban router toi thieu
# Ket qua: bin/cr8806/<ban>/openwrt-...-xiaomi_cr8806-<ban>-*
set -e
cd "$(dirname "$0")/.."

variants="${*:-ap router}"
for v in $variants; do
	[ -f "cr8806/$v/diffconfig" ] || { echo "Khong co ban '$v' (ap|router)"; exit 1; }
done

./scripts/feeds update -a
./scripts/feeds install -a
make -j"$(nproc)" download || true

tdir=bin/targets/qualcommax/ipq50xx
for v in $variants; do
	echo "===== Build ban: $v ====="
	rm -rf files && mkdir files
	cp -a cr8806/files/. files/ 2>/dev/null || true
	cp -a "cr8806/$v/files/." files/
	cat cr8806/diffconfig "cr8806/$v/diffconfig" > .config
	make defconfig
	# Module ngoai cay kernel (ath11k smallbuffers...) khong tu build lai khi cau
	# hinh kernel doi (2 ban khac nhau o netfilter) -> WiFi hong. Luon build lai.
	make package/kernel/mac80211/clean package/kernel/gpio-button-hotplug/clean
	# Khong de kmod cua ban truoc lan vao image ban nay
	rm -rf "$tdir"
	make -j"$(nproc)" download
	make -j"$(nproc)" || make -j1 V=s

	out="bin/cr8806/$v"
	rm -rf "$out" && mkdir -p "$out"
	for f in "$tdir"/*xiaomi_cr8806*; do
		cp "$f" "$out/$(basename "$f" | sed "s/xiaomi_cr8806/xiaomi_cr8806-$v/")"
	done
	(cd "$out" && sha256sum * > sha256sums)
	ls -l "$out"
done
