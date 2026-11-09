#!/bin/sh
# Script kết nối Wi-Fi nhanh cho Allwinner Tina Linux (RTL8189ES)

SSID="$1"
PASS="$2"

if [ -z "$SSID" ]; then
    echo "Sử dụng: $0 <Tên_WiFi> [Mật_khẩu]"
    exit 1
fi

echo "[WIFI] Đang bật card mạng wlan0..."
ifconfig wlan0 up

echo "[WIFI] Tạo file cấu hình /etc/wpa_supplicant.conf..."
if [ -z "$PASS" ]; then
    cat <<EOF > /etc/wpa_supplicant.conf
ctrl_interface=/var/run/wpa_supplicant
network={
    ssid="$SSID"
    key_mgmt=NONE
}
EOF
else
    cat <<EOF > /etc/wpa_supplicant.conf
ctrl_interface=/var/run/wpa_supplicant
network={
    ssid="$SSID"
    psk="$PASS"
    key_mgmt=WPA-PSK
}
EOF
fi

echo "[WIFI] Khởi động wpa_supplicant..."
killall wpa_supplicant 2>/dev/null
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf

echo "[WIFI] Xin cấp IP qua DHCP..."
killall udhcpc 2>/dev/null
udhcpc -i wlan0 -q -n

ifconfig wlan0
echo "[WIFI] Hoàn tất kết nối Wi-Fi!"
