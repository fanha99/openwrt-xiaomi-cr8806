# OpenWrt dumb AP cho Xiaomi CR8806 (M79)

Ghi chép lại toàn bộ những gì đã tìm hiểu, sửa và tạo ra để build OpenWrt
(upstream, có thể cập nhật bản vá) cho Xiaomi CR8806 M79, dùng làm dumb AP.

## 1. Mục tiêu

- OpenWrt gọn nhẹ, LuCI tiếng Anh.
- Cấu hình được LAN, VLAN, WiFi qua LuCI; backup/restore config
  (System > Backup / Flash Firmware).
- Bám theo OpenWrt upstream để nhận bản sửa lỗi.
- Giữ cơ chế dual-boot (rootfs / rootfs_1) của Xiaomi.

### Bố trí mạng (từ 2026-10-23)

| Network | Bridge | Cổng | IP | DHCP |
|---|---|---|---|---|
| `lan` (quản trị) | `br-lan` | lan1, lan2, lan3 (+ WiFi mặc định) | tĩnh 192.168.2.1/24 | dnsmasq cấp .150–.199 |
| `wan` (uplink) | `br-wan` | wan | DHCP client từ router chính | không cấp (`dhcp.wan.ignore=1`) |

- Không firewall/NAT, **IP forwarding tắt** (`/etc/sysctl.d/99-dumb-ap.conf`): máy không
  route giữa lan và wan. Client trên `br-lan` nhận IP nhưng **không có Internet**.
- Muốn client WiFi dùng mạng/Internet của router chính: LuCI → Network → Wireless →
  Edit SSID → *Network* chọn `wan` (bỏ `lan`) → Save & Apply. Client nhận IP từ router chính.
- LuCI/SSH truy cập được từ cả 2 phía: 192.168.2.1 (lan) và IP DHCP của `wan` (xem trong
  LuCI hoặc trong danh sách DHCP của router chính). **Đặt mật khẩu root** (System →
  Administration) trước khi cắm vào mạng chính.

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

- Tên phân vùng **viết hoa** (`0:ART`, `0:APPSBLENV`) trên ROM cũ (kernel 5.4). Kernel
  mainline (parser `qcom,smem-part`) **đổi sang chữ thường**: `0:art`, `0:appsblenv` —
  DTS, caldata và uboot-envtools phải dùng chữ thường.
- MAC WiFi đã có sẵn trong caldata (2.4G = MAC@0x6 + 2, 5G = MAC@0x6 + 1), nên
  không cần patch MAC.
- Caldata 2.4G trong ART khớp 99.9% với BDF board-id 0x10 (M79) → dùng BDF M79.
- U-Boot (`bootmiwifi`) chọn slot theo `flag_last_success` (0 = rootfs, 1 = rootfs_1)
  và `flag_ota_reboot` (=1 → boot slot **còn lại**), rồi truyền `ubi.mtd=rootfs` hoặc
  `ubi.mtd=rootfs_1` trong bootargs. `flag_boot_rootfs` **không** được dùng. Slot lỗi khi
  boot → U-Boot đặt `flag_try_sysN_failed=1` và chuyển sang slot kia. (Theo phân tích
  disassembly của [RA81OpenWRT](https://github.com/lutvzn/RA81OpenWRT), đã kiểm chứng trên
  máy test: `flag_ota_reboot=0`, `flag_last_success=0` → boot `rootfs`.)

## 3. Tình trạng upstream (10/2026)

- OpenWrt `main` đã có target `qualcommax/ipq50xx` (kernel 6.18) và hỗ trợ
  QCN6122 (`ipq5018-qcn6122.dtsi`). Nhánh 25.12 chưa có phần QCN6122.
- **Chưa có CR8806 / Redmi AX3000** trong upstream.
- Mọi máy IPQ50xx 256 MB (CMCC RAX3000Q, PZ-L8, TP-Link RE700X…) đang **tắt WiFi**
  vì ath11k ăn hết RAM. Giải pháp: PR
  [openwrt#21495](https://github.com/openwrt/openwrt/pull/21495) “mac80211: ath11k:
  provide smallbuffers variant” của hzyitc (chưa merge).

## 4. Nguồn

- Repo của dự án này: `https://github.com/fanha99/cr8806-dump-ap` (nhánh `main` =
  nhánh local `cr8806`, remote `fork`). Sau khi rebase: `git push --force-with-lease fork cr8806:main`.
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
     caldata hotplug (`0:art` @0x1000 / @0x26800), sysupgrade.
   - `uboot-envtools`: `0:appsblenv` và `bdata` (offset 0, size 0x10000, sector 0x20000).
5. `cr8806: …` – thư mục `cr8806/` (cấu hình build, script, tài liệu này).

### sysupgrade và dual-boot
`platform.sh` ghi firmware mới vào **đúng slot đang chạy** (đọc `ubi.mtd=` trong
`/proc/cmdline`), đặt `flag_last_success=<slot đang chạy>`, `flag_ota_reboot=0`,
`flag_try_sys1_failed=0`, `flag_try_sys2_failed=0` và **không đụng slot còn lại**.

## 6. Thư mục `cr8806/`

| File | Mục đích |
|---|---|
| `diffconfig` | Cấu hình dumb AP: giữ dnsmasq; bỏ firewall4, nftables, odhcpd, ppp, USB, ext4; LuCI tối giản (luci-mod-admin-full + bootstrap, tiếng Anh) |
| `files/etc/uci-defaults/99-dumb-ap` | Lần boot đầu: `br-lan` = lan1-3, IP 192.168.2.1, DHCP .150–.199; `br-wan` = wan, interface `wan` DHCP client, xoá wan6; hostname `CR8806-AP`. Đánh dấu `system.@system[0].dumb_ap` (=2) để không chạy lại khi sysupgrade giữ config |
| `files/etc/sysctl.d/99-dumb-ap.conf` | Tắt IPv4/IPv6 forwarding (không có firewall) |
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

### 7.1 Build trên GitHub Actions / tạo Release

Workflow `.github/workflows/cr8806.yml` chạy `cr8806/build.sh` trên máy ảo của
GitHub (ubuntu-24.04, 4 nhân). Lần đầu mất khoảng 2–3 giờ, giới hạn 6 giờ. Repo
public nên không tính phí.

Chỉ build để thử (không tạo Release):
```bash
gh workflow run cr8806.yml -R fanha99/cr8806-dump-ap
gh run watch -R fanha99/cr8806-dump-ap
```
Sau khi chạy xong, file nằm ở mục **Artifacts** của lần chạy đó (trên web) hoặc
tải bằng `gh run download <run-id> -R fanha99/cr8806-dump-ap`.

Build rồi tạo Release (tên tag phải bắt đầu bằng `cr8806-`):
```bash
git tag cr8806-2026.10.23
git push fork cr8806-2026.10.23
```
Release gồm `initramfs-uImage.itb`, `squashfs-factory.ubi`, `squashfs-sysupgrade.bin`,
`manifest`, `sha256sums`.

Upload bản build trên máy (không cần chờ GitHub build):
```bash
cd bin/targets/qualcommax/ipq50xx
gh release create cr8806-2026.10.23 -R fanha99/cr8806-dump-ap \
  --title "CR8806 2026.10.23" --notes "Xem cr8806/README.md" \
  *cr8806* sha256sums
```

Repo này là bản copy của OpenWrt nên có sẵn các workflow upstream (Build Kernel,
Build Toolchains, LLM Review...). Chúng tự chạy khi push, vừa lâu vừa vô ích.
Tắt chúng trong **Actions**: chọn từng workflow > `...` > **Disable workflow**,
chỉ giữ `CR8806 build`. Có thể tắt tất cả bằng lệnh:
```bash
R=fanha99/cr8806-dump-ap
gh workflow list -R $R --json name,id --jq '.[] | select(.name != "CR8806 build") | .id' |
  xargs -n1 gh workflow disable -R $R
```

## 8. Cập nhật bản vá upstream

```bash
./cr8806/update-upstream.sh   # rebase các commit lên origin/main mới nhất
./cr8806/build.sh
```
Khi PR #21495 được merge, git sẽ tự bỏ 3 commit trùng khi rebase. Nếu xung đột
(thường ở `11-ath11k-caldata`, `02_network`, `ipq50xx.mk`): giữ phần upstream và
thêm lại mục `xiaomi,cr8806`.

## 9. Cài đặt

**Trước khi làm: backup toàn bộ mtd** (như bản backup đã có) và nên có UART
(115200 8N1).

### 9.0 Chuẩn bị TFTP (cho 9.1 và 9.3)

- PC đặt IP tĩnh `192.168.2.100/24`, cắm dây vào cổng LAN của router.
- Chạy TFTP server (Windows: Tftpd64), thư mục gốc chứa các file image, cho phép qua
  Windows Firewall.
- Đổi tên file cho ngắn, dễ gõ:
  - `...-initramfs-uImage.itb` → `cr.itb`
  - `...-squashfs-factory.ubi` → `cr.ubi`
- Trong U-Boot: **gõ tay từng dòng**, Enter sau mỗi dòng. Không dán nhiều lệnh một
  lúc, không nối bằng `;` (UART bị rớt ký tự → lỗi `flags type check failure`).
  Tắt bộ gõ tiếng Việt (Unikey/EVKey).
- Vào U-Boot: bật nguồn, bấm phím bất kỳ khi thấy `Hit any key to stop autoboot`.

### 9.1 Boot thử initramfs (chỉ chạy trong RAM, KHÔNG ghi flash)

Gõ từng dòng:

```
setenv ipaddr 192.168.2.1
```
```
setenv serverip 192.168.2.100
```
```
printenv ipaddr serverip
```
→ phải in ra đúng 2 IP ở trên.
```
ping 192.168.2.100
```
→ phải thấy `host 192.168.2.100 is alive`. Nếu không: đổi cổng LAN, kiểm tra IP/firewall PC.
```
tftpboot 0x44000000 cr.itb
```
→ chờ chạy hết dấu `#`, cuối cùng có `Bytes transferred = 125xxxxx`.
```
bootm 0x44000000#config@mp02.1
```

Không dùng `saveenv` ở bước này → rút điện là máy về firmware cũ. Sau khi boot xong
(~1 phút), làm các bước kiểm tra ở mục 10 (bỏ qua 10.6 sysupgrade).

### 9.2 Cài vào flash từ firmware đang chạy (giữ dual-boot)

Từ firmware đang chạy (stock Xiaomi có SSH, hoặc ROM OpenWrt/QSDK cũ) – ghi vào
**slot đang không chạy**. Chép `cr.ubi` vào `/tmp` rồi gõ từng dòng:

```sh
cd /tmp
cat /proc/mtd
cat /proc/cmdline
```
→ `/proc/mtd`: xác nhận `rootfs` = mtd18, `rootfs_1` = mtd19.
→ `/proc/cmdline`: xem đang chạy `ubi.mtd=rootfs` hay `ubi.mtd=rootfs_1`.

**Nếu đang chạy `rootfs_1`** → ghi vào `rootfs` (slot 1):
```sh
ubiformat /dev/mtd18 -y -f /tmp/cr.ubi
nvram set flag_try_sys1_failed=0
nvram set flag_last_success=0
nvram set flag_ota_reboot=0
nvram commit
reboot
```

**Nếu đang chạy `rootfs`** → ghi vào `rootfs_1` (slot 2):
```sh
ubiformat /dev/mtd19 -y -f /tmp/cr.ubi
nvram set flag_try_sys2_failed=0
nvram set flag_last_success=1
nvram set flag_ota_reboot=0
nvram commit
reboot
```

Trên ROM OpenWrt cũ không có `nvram`: thay `nvram set X=Y` bằng `fw_setenv X Y`
và bỏ dòng `nvram commit`.

**Từ initramfs của bản này** (mục 9.1, đã làm trên máy test): PC/WSL truyền thẳng
image qua SSH, không cần chép vào RAM router (gõ trên PC/WSL, 1 dòng):
```sh
ssh root@192.168.2.1 "ubiformat /dev/mtd19 -y -f - -S $(stat -c %s cr.ubi)" < cr.ubi
```
Rồi trên router:
```sh
fw_setenv flag_try_sys2_failed 0
fw_setenv flag_last_success 1
fw_setenv flag_ota_reboot 0
reboot
```
(Ghi `rootfs` thì dùng `/dev/mtd18` và `flag_try_sys1_failed 0`, `flag_last_success 0`.)

### 9.3 Cài vào flash qua U-Boot (TFTP)

Làm các bước chuẩn bị ở 9.0, rồi gõ từng dòng (ghi vào slot 2 = `rootfs_1`):

```
setenv ipaddr 192.168.2.1
```
```
setenv serverip 192.168.2.100
```
```
ping 192.168.2.100
```
```
tftpboot 0x44000000 cr.ubi
```
→ cuối cùng có `Bytes transferred = 138xxxxx`.
```
flash rootfs_1
```
```
setenv flag_try_sys2_failed 0
```
```
setenv flag_last_success 1
```
```
setenv flag_ota_reboot 0
```
```
saveenv
```
```
reset
```

Ghi vào slot 1 (`rootfs`) thì thay bằng `flash rootfs`, `flag_try_sys1_failed 0`,
`flag_last_success 0`.

### 9.4 Chuyển sang slot kia

Trong OpenWrt (SSH `root@192.168.2.1`), về slot 1 (`rootfs`):
```sh
fw_setenv flag_last_success 0
fw_setenv flag_ota_reboot 0
reboot
```
Về slot 2 (`rootfs_1`): dùng `flag_last_success 1`. Trong U-Boot: `setenv` 2 biến đó,
rồi `saveenv`, `reset`.

## 10. Kiểm tra sau khi khởi động

Đăng nhập: cắm PC vào lan1, lan2 hoặc lan3 (cổng wan là `br-wan`, nhận IP từ router chính).
PC để DHCP (nhận 192.168.2.150–199) hoặc IP tĩnh `192.168.2.100/24` (cùng IP đã dùng
cho TFTP ở 9.0). Initramfs/bản build trước 2026-10-23 không có DHCP: phải đặt IP tĩnh. Rồi:
```sh
ssh root@192.168.2.1
```
Hoặc dùng luôn shell trên UART (Enter để ra dấu nhắc `root@CR8806-AP:~#`).
LuCI: http://192.168.2.1 (user `root`, chưa có mật khẩu).

Gõ từng lệnh dưới đây và gửi lại kết quả nếu khác với "mong đợi".

### 10.1 Hệ thống, flash

```sh
cat /proc/cmdline
```
→ có `ubi.mtd=rootfs` hoặc `ubi.mtd=rootfs_1` (initramfs thì có thể không có).
```sh
cat /proc/mtd
```
→ tên phân vùng chữ thường: `0:art`, `0:appsblenv`, `rootfs`, `rootfs_1`, `bdata`…
```sh
dmesg | grep -iE 'ubi|nand|error|fail'
```
→ không có lỗi UBI/NAND (initramfs: không có dòng UBI là bình thường).

### 10.2 Mạng (4 cổng, IP, MAC)

```sh
ip link
```
→ có `eth0`, `eth1`, `lan1@eth1`, `lan2@eth1`, `lan3@eth1`, `wan@eth0`, `br-lan`; cổng có
cắm dây có `LOWER_UP`. (Máy dùng `ip` của busybox: không có tuỳ chọn `-br`.)
```sh
ip addr show br-lan
```
→ có dòng `inet 192.168.2.1/24`.
```sh
ls /sys/class/net/br-lan/brif /sys/class/net/br-wan/brif
```
→ `br-lan`: `lan1  lan2  lan3` (+ `phy*-ap0` khi bật WiFi); `br-wan`: `wan`.
```sh
ifstatus wan | grep -A2 ipv4-address
```
→ khi cổng wan cắm vào router chính: có IP do router chính cấp.
```sh
dmesg | grep -iE 'qca8k|link is up'
```
→ switch QCA8337 nhận, cổng cắm dây báo `Link is Up - 1Gbps/Full`.
```sh
cat /sys/class/net/eth0/address /sys/class/net/eth1/address
```
→ MAC lấy từ ART (giống MAC0/MAC1 U-Boot in ra lúc boot, dạng `d4:35:38:...`),
không phải MAC ngẫu nhiên.

Thử cắm PC lần lượt vào từng cổng lan1, lan2, lan3, mỗi lần chạy:
```sh
ping -c 3 192.168.2.100
```

### 10.3 WiFi

```sh
dmesg | grep -i ath11k
```
→ **không** còn dòng `failed to load CAL data` / `failed to load board data`.
```sh
dmesg | grep -A4 'fatal error'
```
→ không có gì (nếu có: firmware WiFi crash, gửi toàn bộ kết quả lệnh này).
```sh
ls -l /lib/firmware/ath11k/
```
→ có `cal-ahb-c000000.wifi.bin` và `cal-ahb-b00a040.wifi.bin` (mỗi file 131072 byte).
```sh
iw phy
```
→ có 2 phy: 1 cái băng 2.4 GHz, 1 cái băng 5 GHz.
```sh
iw dev
```

Bật WiFi để thử (mặc định OpenWrt tắt WiFi), gõ từng dòng:
```sh
uci set wireless.radio0.disabled=0
uci set wireless.radio1.disabled=0
uci commit wireless
wifi
```
Đợi ~30 giây rồi:
```sh
iw dev
```
→ có 2 interface `phy0-ap0` và `phy1-ap0` với `ssid OpenWrt`.
```sh
logread | grep -iE 'hostapd|ath11k'
```
→ có `AP-ENABLED` cho cả 2. Dùng điện thoại kết nối SSID `OpenWrt` (không mật khẩu,
chỉ để test), đặt IP tĩnh 192.168.2.x rồi mở http://192.168.2.1.

### 10.4 RAM

```sh
free
```
→ chạy **sau khi** bật cả 2 WiFi; cột `available` nên còn > 40000 (KB).
```sh
dmesg | grep -iE 'oom|out of memory'
```
→ không có gì.

### 10.5 U-Boot env

```sh
fw_printenv | grep flag_
```
→ in ra các biến `flag_boot_rootfs`, `flag_last_success`… (không báo lỗi CRC/không mở
được thiết bị).
```sh
fw_printenv -c /etc/fw_sys.config
```
→ đọc được env trong `bdata` (chỉ đọc, đừng sửa).

### 10.6 sysupgrade (chỉ khi đã cài vào flash, không áp dụng cho initramfs)

```sh
cat /proc/cmdline
```
→ ghi nhớ đang chạy slot nào. Sau đó trong LuCI: System → Backup / Flash Firmware →
flash `...-squashfs-sysupgrade.bin` (giữ cấu hình). Sau khi boot lại:
```sh
cat /proc/cmdline
fw_printenv | grep flag_
```
→ vẫn đúng slot cũ, cấu hình (IP, WiFi) còn nguyên. Rồi thử 9.4 để chắc slot kia vẫn
boot được firmware cũ.

### 10.7 LED, nút bấm

```sh
ls /sys/class/leds
```
→ `blue:status`, `yellow:status`, `blue:wan`, `yellow:wan`.
```sh
echo 1 > /sys/class/leds/yellow:wan/brightness
```
→ đèn internet màu vàng sáng.
```sh
echo 0 > /sys/class/leds/yellow:wan/brightness
```
Nút bấm:
```sh
cat /sys/kernel/debug/gpio | grep -iE 'reset|mesh'
```
→ chạy 2 lần: một lần thả, một lần **đang giữ** nút; trạng thái `hi`/`lo` phải đổi.
(Không giữ reset quá 5 giây khi đã cài flash → sẽ reset cấu hình.)

### 10.8 Backup / restore cấu hình

LuCI → System → Backup / Flash Firmware → **Generate archive** (tải về file
`.tar.gz`). Đổi thử 1 thứ (VD hostname), rồi **Upload archive** file vừa tải →
sau khi khởi động lại, hostname về như cũ.

## 11. Nhật ký build

Xem mục dưới (cập nhật mỗi lần build có lỗi/sửa).

### 2026-10-23 – build đầu tiên: THÀNH CÔNG (chưa test trên máy thật)
- Nền: upstream `main` @ `84d081bf62`, kernel 6.18.55, gcc 14.4, WSL Ubuntu 26.04, 8 nhân, ~1 giờ.
- Không có lỗi build. Cảnh báo kconfig (qt5base, squeezelite, openvswitch…) đến từ
  feeds, không liên quan, bỏ qua được.
- Image (111 gói): `factory.ubi` 13.9 MB (vừa slot rootfs 36 MB), `sysupgrade.bin` 13.0 MB,
  `initramfs-uImage.itb` 12.5 MB.
- Đã kiểm tra trong rootfs/DTB: board-2.bin đúng `variant=Xiaomi-CR8806`, module ath11k
  build từ `mac80211-smallbuffers`, caldata `0:ART` @0x1000/@0x26800, script
  `99-dumb-ap` (IP 192.168.2.1), không có firewall/dnsmasq/odhcpd/ppp.
- Sửa trong quá trình làm: bỏ patch MAC WiFi (caldata gốc đã có MAC đúng; bản đầu gán
  ngược 2.4G/5G).

### 2026-10-23 – test initramfs lần 1 trên máy thật: WiFi lỗi → đã sửa
- Boot initramfs qua TFTP OK, vào được shell, `free`: total 183 MB, available ~96 MB.
- U-Boot: dán cả dòng `setenv ...; setenv ...` qua UART bị hỏng ký tự (`flags type
  check failure`) → gõ tay từng lệnh, tắt bộ gõ tiếng Việt.
- Lỗi: `qmi failed to load CAL data file:cal-ahb-c000000.wifi.bin` / `failed to load
  board data file: -12` cho cả 2 radio. Firmware q6 và QMI đã lên (board_id 0xff đúng).
- Nguyên nhân: parser `qcom,smem-part` của kernel 6.18 đổi tên phân vùng sang chữ thường
  (`0:art`), còn cấu hình dùng `0:ART` (lấy từ ROM cũ) → script không tìm thấy phân vùng
  để trích caldata; nvmem MAC trong DTS cũng không gắn được.
- Sửa: `0:art` trong DTS + 11-ath11k-caldata, `0:appsblenv` trong uboot-envtools.
- Build lại (incremental, ~15 phút): OK. Đã kiểm tra DTB có `0:art`, rootfs có caldata
  `0:art` và uboot-envtools `0:appsblenv`.
- README: viết lại mục 9 (TFTP gõ từng dòng, đổi tên file `cr.itb`/`cr.ubi`) và mục 10
  (lệnh kiểm tra cụ thể + kết quả mong đợi).

### 2026-10-23 – test initramfs lần 2: firmware WiFi crash → đổi sang memory mode 2
- Tên phân vùng đã đúng (`0:art`), caldata được trích, BDF được firmware nhận.
- Q6 firmware crash ngay khi xử lý BDF/caldata của radio 2.4G:
  `fatal error received: ... phyrf_bdf.c:605 Assertion 0 failed` (process `wlan0`),
  sau đó 5G báo `-104` (mất QMI) và 2.4G `-110` (timeout).
- `eth1` (LAN) nhận MAC ngẫu nhiên `62:db:...` dù DTS trỏ nvmem `0:art`+0x6.
- Đối chiếu với [RA81OpenWRT](https://github.com/lutvzn/RA81OpenWRT) (Redmi AX3000, cùng
  mạch, WiFi đã chạy trên OpenWrt 25.12 với cùng firmware WLAN.HK.2.7.0.1 và BDF
  hzyitc): họ dùng **FW memory mode 2** (giống firmware gốc Xiaomi `tgt-mem-mode = 2`
  cho máy 256 MB) và mở rộng `tz_region` lên 4 MiB như DT gốc. Bản này đang dùng mode 1.
- Sửa:
  - DTS: `qcom,ath11k-fw-memory-mode = <2>` cho cả 2 radio, `&tz_region` 0x400000.
  - 02_network: lấy MAC LAN từ `0:art`+0x6, gán cho `eth1` và `lan` (không phụ thuộc nvmem).
- Lưu ý: RA81 (M81) dùng BDF board-id 36 (0x24); CR8806 M79 dùng board-id 16 (0x10) –
  caldata ART của máy backup khớp 99.9% với BDF id 16. Nếu máy test vẫn crash, thử
  BDF id 36 (board ID nằm ở byte `0:art`+0x103a: máy backup = 0x10 → M79; xem bằng `hexdump -C -s 0x1030 -n 16 /dev/mtd13`).

### 2026-10-23 – test initramfs lần 3: vẫn crash `phyrf_bdf.c:605` → vá BDF 2.4G
- Mode 2 đã có hiệu lực nhưng Q6 vẫn assert `phyrf_bdf.c:605 Assertion 0 failed` ở `wlan0`.
- Máy test: board ID `0:art`+0x103a = 0x10 → M79 (đúng BDF id 16).
- So sánh BDF id 16 (M79) với id 36 (M81, chạy được trên RA81): byte **0x45c** = `03` ở
  id 16, `00` ở id 36 và QCN6122 id 96. Trên forum OpenWrt (Linksys MX2000, cùng firmware
  WLAN.HK.2.7.0.1-01744) đúng lỗi `phyrf_bdf.c:605` được sửa bằng cách đổi 0x45c từ 3 → 0
  ("This value is 3 in 2.4" – hzyitc).
- Sửa: vá `board-xiaomi_cr8806.ipq5018` bằng
  [ath11k_bdf_tool.py](https://github.com/testuser7/ath_bdf_tool) `-p bdf 0x45c 00`
  (checksum @0xa cập nhật 0x2a75 → 0x2a76), đóng gói lại vào board-2.bin cùng tên.
  Payload md5 sau vá: `82e6530034c5b1ce97fbf1d560287bae`.
- README: `ip` của busybox không có `-br`, không có lệnh `bridge` → sửa lệnh ở mục 10.2.
- eth1 vẫn MAC ngẫu nhiên dù 02_network đã lấy MAC từ `0:art`+0x6 → đang điều tra.

### 2026-10-23 – test initramfs lần 4: tìm ra nguyên nhân gốc – NAND đọc sai ECC
- Vẫn crash `phyrf_bdf.c:605` sau khi vá BDF.
- Dump toàn bộ mtd của máy test qua SSH (chỉ đọc) và so với bản backup (đọc bằng kernel
  QSDK 5.4 của hzyitc): **mọi phân vùng đều khác**, kể cả `0:appsbl` và `0:appsbl_1`
  (2 bản U-Boot giống hệt nhau trên backup nhưng đọc ra khác nhau trên máy test).
- Mẫu lỗi: dữ liệu lệch thêm 4 byte sau mỗi codeword 512 byte → bố trí ECC sai.
  U-Boot Xiaomi dùng **ECC 8-bit** (`Serial NAND ... ECC:8-bit`), DTS thiếu
  `nand-ecc-strength` nên driver `spi-qpic-snand` tự chọn ECC 4-bit theo chip
  GD5F1GQ5REYIG. Hệ quả: caldata WiFi đọc ra bị hỏng (→ firmware assert), UBI báo
  `unable to read from mtd21`, MAC `eth1` không đọc được.
- Sửa: thêm `nand-ecc-step-size = <512>; nand-ecc-strength = <8>;` vào DTS (giống
  Xiaomi AX6000, Redmi AX5400 và RA81).
- **CẢNH BÁO: KHÔNG flash `factory.ubi`/`sysupgrade.bin` của các bản build trước commit
  này** – ghi bằng ECC 4-bit thì U-Boot (ECC 8-bit) không đọc được → máy không boot slot đó.
- Bản vá BDF 0x45c (lần 3) vẫn giữ: firmware 2.7 yêu cầu giá trị 0 (MX2000 / RA81 M81).

### 2026-10-23 – test initramfs lần 5 (ECC 8-bit): WiFi CHẠY
- NAND đọc đúng: md5 của `0:sbl1`, `0:qsee`, `0:qsee_1`, `0:appsbl`, `0:appsbl_1` trên máy
  test trùng với bản backup (ART/bdata khác vì là dữ liệu riêng từng máy). UBI attach
  `mtd21` không lỗi.
- WiFi: không còn crash; `phy0` 2.4G (ch1 HE20, 23 dBm), `phy1` 5G (ch36 HE80, 24 dBm),
  cả 2 `AP-ENABLED`. MAC WiFi lấy từ caldata: 5G = LAN+1, 2.4G = LAN+2 (giống stock).
- Ethernet: `eth0`/wan = ART+0x0, `eth1`/br-lan = ART+0x6 (đúng MAC U-Boot in ra).
- RAM (initramfs, rootfs nằm trong RAM): available ~55 MB khi chưa bật WiFi, ~34 MB khi
  bật cả 2 AP. Cài vào flash sẽ dư hơn (rootfs không chiếm RAM).
- `fw_printenv` đọc được env (`flag_*`); `fw_printenv -c /etc/fw_sys.config` đọc được bdata.
- LED: `blue:status`, `yellow:status`, `blue:wan`, `yellow:wan` có mặt.
- Chưa test: client kết nối WiFi/throughput, nút bấm, cài vào flash + dual-boot, sysupgrade.

### 2026-10-23 – cài vào flash cả 2 slot: BOOT OK
- Hai slot cũ trên máy test (một bản OpenWrt 6.12 "Redmi AX3000 / Xiaomi CR880X
  (dual-slot)") đều hỏng → người dùng đồng ý ghi đè cả hai.
- Từ initramfs: `ubiformat /dev/mtd19` rồi `/dev/mtd18` với `factory.ubi` (truyền qua SSH
  stdin, `-f - -S <size>`); đọc lại 2 slot: volume `kernel`/`rootfs` trùng md5 với image,
  có `rootfs_data` (autoresize).
- Phát hiện: `bootmiwifi` chọn slot theo `flag_last_success` + `flag_ota_reboot`, không
  theo `flag_boot_rootfs` (env lúc đó `flag_ota_reboot=1, flag_last_success=1` → sẽ boot
  `rootfs`). Đặt `flag_ota_reboot=0, flag_last_success=0`, reboot.
- Kết quả: boot từ flash ~40 s, cmdline `ubi.mtd=rootfs ... root=/dev/ubiblock0_1`,
  overlay ubifs 13.8 MB, IP 192.168.2.1, RAM available ~61 MB (chưa bật WiFi).
- Sửa `platform.sh` (sysupgrade): đặt `flag_last_success=<slot>` và `flag_ota_reboot=0`
  (trước đây đặt `flag_boot_rootfs` – vô tác dụng; nếu env còn `flag_ota_reboot=1` thì
  sau sysupgrade U-Boot sẽ boot nhầm slot kia). README mục 9.2–9.4 viết lại theo logic này.

### 2026-10-23 – sysupgrade OK; thêm dnsmasq, tách `br-wan`
- Test sysupgrade (giữ config) bằng bản có `platform.sh` mới, cố ý đặt `flag_ota_reboot=1`
  trước: sau ~90 s boot lại đúng `rootfs`, `flag_ota_reboot` được xoá về 0, cấu hình WiFi
  và hostname còn nguyên.
- Theo yêu cầu: image có sẵn **dnsmasq**; cổng **wan tách ra `br-wan`** (interface `wan`
  DHCP client), `br-lan` = lan1-3 với DHCP .150–.199 (tránh .100 của PC/TFTP).
- Tắt IP forwarding (`/etc/sysctl.d/99-dumb-ap.conf`) vì không có firewall: trước đó
  `net.ipv4.ip_forward=1` (mặc định OpenWrt) → máy sẽ route lan↔wan không lọc, không NAT.
- Test bằng `sysupgrade -n` (cấu hình mới hoàn toàn): `br-lan`=lan1-3, `br-wan`=wan,
  dnsmasq chạy, `dhcp.wan.ignore=1`, RAM available ~58 MB (chưa WiFi), ~45 MB (2 AP bật).
- Lưu ý: máy đã cài bản cũ (`dumb_ap=1`) khi sysupgrade giữ config sẽ **không** tự đổi sang
  bố trí mới – sửa trong LuCI hoặc sysupgrade không giữ config.

### 2026-10-23 – chuyển sang "router tối thiểu" (vẫn dùng làm AP được)
- Theo yêu cầu: thêm `firewall4` (+nftables, NAT), `kmod-nft-offload` (bật
  `flow_offloading`), `luci-app-firewall`, `ppp`/`ppp-mod-pppoe`/`luci-proto-ppp`,
  `odhcpd-ipv6only`/`luci-proto-ipv6`, `irqbalance` (bật). Không UPnP, không DDNS.
- `99-dumb-ap`: tạo lại `wan6` (DHCPv6 trên `@wan`), bật flow offload và irqbalance, marker
  `dumb_ap=3`. Bỏ `/etc/sysctl.d/99-dumb-ap.conf` (router cần forwarding; firewall lo việc chặn).
- Cài thêm kmod qua SSH lên máy đang chạy **không được**: bật module netfilter làm đổi cấu
  hình kernel → hash `kernel=` khác → apk từ chối. Phải build cả image.
- **Bẫy build**: sau khi đổi cấu hình kernel, `mac80211-smallbuffers` (ath11k) **không tự
  build lại** → module cũ chạy trên kernel mới (đổi layout `sk_buff`/`net_device` do
  `NET_INGRESS/EGRESS`…) → WiFi lỗi `unexpected rx length (nbytes 20, max 0)`,
  `failed to connect to HTC: -110`. Sửa: `make package/kernel/mac80211/clean
  package/kernel/gpio-button-hotplug/clean` rồi build lại. **Mỗi khi đổi gói kmod/netfilter
  trong diffconfig phải làm bước này** (build.sh đã thêm).
- Test (`sysupgrade -n`, 141 gói, sysupgrade.bin ~14 MB): `fw4 check` OK, bảng `inet fw4`,
  zone lan/wan(+wan6), flow offload, irqbalance/odhcpd/dnsmasq chạy, 2 AP lên.
- RAM available ~30 MB khi bật 2 AP (bản AP-only trước đó ~45 MB). Tiến trình lớn nhất:
  hostapd ~3.5 MB, wpa_supplicant ~3.1 MB, netifd ~2.5 MB, rpcd ~2 MB.
