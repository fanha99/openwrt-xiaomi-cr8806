# OpenWrt dumb AP cho Xiaomi CR8806 (M79)

Ghi chép lại toàn bộ những gì đã tìm hiểu, sửa và tạo ra để build OpenWrt
(upstream, có thể cập nhật bản vá) cho Xiaomi CR8806 M79, dùng làm dumb AP.

## 1. Mục tiêu

- OpenWrt gọn nhẹ, LuCI tiếng Anh.
- Cấu hình được LAN, VLAN, WiFi qua LuCI; backup/restore config
  (System > Backup / Flash Firmware).
- Bám theo OpenWrt upstream để nhận bản sửa lỗi.
- Giữ cơ chế dual-boot (rootfs / rootfs_1) của Xiaomi.

## 2. Phần cứng (đã xác minh từ backup flash của 1 máy thật)

| Thành phần | Chi tiết |
|---|---|
| SoC | IPQ5000 (họ IPQ5018), 2.4G WiFi tích hợp |
| WiFi 5G | QCN6102 (driver ath11k gọi là QCN6122) |
| RAM / Flash | 256 MB / 128 MB SPI-NAND |
| Switch | QCA8337: phy0..2 = lan1..3, phy3 = wan, phy4 nối GE-PHY của SoC |
| Board | giống Redmi AX3000 (RA81) / CR8808 / CR8809 bản M79 |

Bảng phân vùng gốc (`/proc/mtd`):

```
mtd10 0:APPSBLENV 0x80000   (u-boot env ở offset 0, size 0x10000)
mtd13 0:ART       0x100000  (MAC @0x0 và @0x6, caldata 2.4G @0x1000, 5G @0x26800)
mtd15 bdata       0x80000   (env phụ, offset 0, size 0x10000)
mtd18 rootfs      0x2400000 (slot 1)
mtd19 rootfs_1    0x2400000 (slot 2)
mtd20 overlay, mtd21 data
```

- Tên phân vùng **viết hoa** (`0:ART`, `0:APPSBLENV`).
- MAC WiFi đã có sẵn trong caldata (2.4G = MAC@0x6 + 2, 5G = MAC@0x6 + 1), nên
  không cần patch MAC.
- Caldata 2.4G trong ART khớp 99.9% với BDF board-id 0x10 (M79) → dùng BDF M79.
- U-Boot chọn slot theo `flag_boot_rootfs` (0 = rootfs, 1 = rootfs_1) và truyền
  `ubi.mtd=rootfs` hoặc `ubi.mtd=rootfs_1` trong bootargs.

## 3. Tình trạng upstream (10/2026)

- OpenWrt `main` đã có target `qualcommax/ipq50xx` (kernel 6.18) và hỗ trợ
  QCN6122 (`ipq5018-qcn6122.dtsi`). Nhánh 25.12 chưa có phần QCN6122.
- **Chưa có CR8806 / Redmi AX3000** trong upstream.
- Mọi máy IPQ50xx 256 MB (CMCC RAX3000Q, PZ-L8, TP-Link RE700X…) đang **tắt WiFi**
  vì ath11k ăn hết RAM. Giải pháp: PR
  [openwrt#21495](https://github.com/openwrt/openwrt/pull/21495) “mac80211: ath11k:
  provide smallbuffers variant” của hzyitc (chưa merge).

## 4. Nguồn

- Upstream: `https://github.com/openwrt/openwrt.git` nhánh `main` (remote `origin`).
- PR smallbuffers: `https://github.com/hzyitc/openwrt-redmi-ax3000.git`, nhánh
  `ath11k-smallbuffers` (remote `hzyitc`).
- DTS/board-data tham khảo: nhánh `ipq50xx-pr` của hzyitc (`ipq5000-ax3000.dts`,
  `board-redmi_ax3000.*`).

## 5. Các commit trên nhánh `cr8806`

1. `mac80211: fix extra cflags` – từ PR #21495
2. `mac80211: ath11k: provide smallbuffers variant` – từ PR #21495
3. `qualcommax: ipq50xx: pz-l8: enable WiFi` – từ PR #21495
4. `qualcommax: ipq50xx: add support for Xiaomi CR8806 (M79)`:
   - `target/linux/qualcommax/dts/ipq5018-cr8806.dts` – dựa trên DTS CMCC PZ-L8
     (cùng thiết kế), GPIO lấy từ DTS AX3000 của hzyitc:
     LED 17/19/20/22, nút reset 25, mesh 23, reset switch 26, reset QCN6102 27.
     Giữ `ubi.mtd` do U-Boot truyền, chỉ ghi đè `root=/dev/ubiblock0_1`.
   - `target/linux/qualcommax/image/ipq50xx.mk` – `Device/xiaomi_cr8806`
     (`config@mp02.1`, UBI, `kmod-ath11k-smallbuffers`).
   - `package/firmware/ipq-wifi/` – gói `ipq-wifi-xiaomi_cr8806`; board-2.bin
     trong `src/` được đóng gói lại (ath11k-bdencoder) từ BDF M79 (id 16) và
     QCN6102 (id 96) với tên `bus=ahb,qmi-chip-id=0,qmi-board-id=255,variant=Xiaomi-CR8806`
     (firmware mainline báo board-id 255).
   - `base-files`: 02_network (lan1-3 + wan, conduit eth1/eth0), 01_leds,
     caldata hotplug (`0:ART` @0x1000 / @0x26800), sysupgrade.
   - `uboot-envtools`: `0:APPSBLENV` và `bdata` (offset 0, size 0x10000, sector 0x20000).
5. `cr8806: …` – thư mục `cr8806/` (cấu hình build, script, tài liệu này).

### sysupgrade và dual-boot
`platform.sh` ghi firmware mới vào **đúng slot đang chạy** (đọc `ubi.mtd=` trong
`/proc/cmdline`), đặt lại các cờ `flag_boot_rootfs`, `flag_last_success`,
`flag_try_sysN_failed=0`, `flag_boot_success=1` và **không đụng slot còn lại**.

## 6. Thư mục `cr8806/`

| File | Mục đích |
|---|---|
| `diffconfig` | Cấu hình dumb AP: bỏ dnsmasq, firewall4, nftables, odhcpd, ppp, USB, ext4; LuCI tối giản (luci-mod-admin-full + bootstrap, tiếng Anh) |
| `files/etc/uci-defaults/99-dumb-ap` | Lần boot đầu: IP LAN 192.168.2.1, cho cổng `wan` vào `br-lan`, xoá interface wan/wan6, hostname `CR8806-AP`. Đánh dấu `system.@system[0].dumb_ap=1` để không chạy lại khi sysupgrade giữ config |
| `build.sh` | feeds update/install → copy `files/` + `diffconfig` → `make defconfig` → build |
| `update-upstream.sh` | `git fetch` + `git rebase origin/main` để nhận bản vá upstream |

IP quản trị mặc định: **192.168.2.1/24** (đặt trong `99-dumb-ap`, chỉ chạy ở lần boot đầu; đổi sau trong LuCI: Network > Interfaces > lan).

## 7. Build

```bash
# Ubuntu (WSL): gói cần thiết
sudo apt install build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
  gettext git libncurses-dev libssl-dev python3-setuptools rsync swig unzip zlib1g-dev file wget

cd ~/openwrt-cr8806
# WSL: bỏ đường dẫn Windows (có dấu cách) khỏi PATH
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd:)
./cr8806/build.sh
```

Kết quả: `bin/targets/qualcommax/ipq50xx/`
- `openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-factory.ubi` – flash lần đầu
- `openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-sysupgrade.bin` – nâng cấp
  từ OpenWrt bản này về sau

## 8. Cập nhật bản vá upstream

```bash
./cr8806/update-upstream.sh   # rebase các commit lên origin/main mới nhất
./cr8806/build.sh
```
Khi PR #21495 được merge, git sẽ tự bỏ 3 commit trùng khi rebase. Nếu xung đột
(thường ở `11-ath11k-caldata`, `02_network`, `ipq50xx.mk`): giữ phần upstream và
thêm lại mục `xiaomi,cr8806`.

## 9. Cài đặt (giữ dual-boot)

**Trước khi làm: backup toàn bộ mtd** (như bản backup đã có) và nên có UART.

Từ firmware đang chạy (stock Xiaomi có SSH, hoặc ROM OpenWrt/QSDK cũ) – ghi vào
**slot đang không chạy**:

```sh
cd /tmp   # chép file factory.ubi vào đây
cat /proc/mtd            # xác nhận rootfs=mtd18, rootfs_1=mtd19
cat /proc/cmdline        # xem đang chạy ubi.mtd=rootfs hay rootfs_1

# Nếu đang chạy rootfs_1 -> ghi vào rootfs (slot 1):
ubiformat /dev/mtd18 -y -f openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-factory.ubi
nvram set flag_try_sys1_failed=0; nvram set flag_boot_rootfs=0; nvram set flag_last_success=0; nvram commit
# (trên OpenWrt cũ dùng fw_setenv thay cho nvram set)

# Nếu đang chạy rootfs -> ghi vào rootfs_1 (slot 2):
ubiformat /dev/mtd19 -y -f openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-factory.ubi
nvram set flag_try_sys2_failed=0; nvram set flag_boot_rootfs=1; nvram set flag_last_success=1; nvram commit

reboot
```

Qua U-Boot (UART, 115200):
```
setenv ipaddr 192.168.1.2; setenv serverip 192.168.1.1
tftpboot openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-factory.ubi
flash rootfs_1
setenv flag_try_sys2_failed 0; setenv flag_boot_rootfs 1; setenv flag_last_success 1
saveenv; reset
```

Quay lại slot cũ: đặt `flag_boot_rootfs` về slot kia (`fw_setenv` trong OpenWrt).

## 10. Việc cần kiểm tra trên máy thật

- [ ] Boot được, `logread`/`dmesg` không lỗi NAND/UBI.
- [ ] 4 cổng mạng (lan1-3, wan) đều link và nằm trong br-lan.
- [ ] `dmesg | grep ath11k`: 2 radio lên, load đúng `variant=Xiaomi-CR8806`.
- [ ] `free`: còn RAM sau khi bật cả 2 WiFi.
- [ ] `fw_printenv` đọc được env (`0:APPSBLENV`).
- [ ] sysupgrade giữ đúng slot; slot còn lại vẫn boot được.
- [ ] LED, nút reset (giữ để reset) hoạt động.

## 11. Nhật ký build

Xem mục dưới (cập nhật mỗi lần build có lỗi/sửa).
