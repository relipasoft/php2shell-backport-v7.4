#!/usr/bin/env bash
# Cập nhật php7.4 (PPA ondrej) lên bản đã vá PHP2Shell (CVE-2026-109618, CVE-2026-109619) trên Ubuntu 18.04.
#
#   sudo bash install.sh <thư mục out/>
#
# Script chỉ: chép .deb vào /opt/php2shell-bionic, thêm 1 nguồn apt local, nâng các gói php7.4 đã cài.
# Không cài thêm extension, không gỡ gói nào, không restart dịch vụ.
set -euo pipefail

SRC_DIR="${1:?Cách dùng: sudo bash install.sh <thư mục chứa .deb và Packages.gz>}"
REPO_DIR=/opt/php2shell-bionic
LIST_FILE=/etc/apt/sources.list.d/relipa-php2shell.list
export DEBIAN_FRONTEND=noninteractive

if ! grep -q 'VERSION_CODENAME=bionic' /etc/os-release 2>/dev/null; then
  echo "Chỉ dành cho Ubuntu 18.04 (bionic)." >&2; exit 1
fi
if ! dpkg-query -W -f='${Status} ${Version}\n' php7.4-common 2>/dev/null | grep -q '^install ok installed 1\?:\?7\.4\.'; then
  echo "Máy này chưa cài php7.4-common. Script chỉ cập nhật, không cài mới." >&2; exit 1
fi
if [ ! -f "$SRC_DIR/Packages.gz" ]; then
  echo "Không thấy $SRC_DIR/Packages.gz." >&2; exit 1
fi

echo "== 0. Gói php hiện tại"
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' 'php*' 'libapache2-mod-php*' 2>/dev/null | awk '$1=="ii"{print $2, $3}'

echo "== 1. Chép .deb vào $REPO_DIR"
mkdir -p "$REPO_DIR"
cp -r "$SRC_DIR"/. "$REPO_DIR"/
(cd "$REPO_DIR" && sha256sum -c --quiet SHA256SUMS)

echo "== 2. Thêm nguồn apt local"
echo "deb [trusted=yes] file:$REPO_DIR ./" > "$LIST_FILE"
apt-get update -qq -o Dir::Etc::sourcelist="$LIST_FILE" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
# Cập nhật index Ubuntu để cài được thư viện còn thiếu (libicu60, libonig4, libargon2-0...)
apt-get update -qq || echo "   (cảnh báo: apt-get update có lỗi ở một nguồn khác, vẫn tiếp tục)"

# Chỉ các gói đang cài VÀ có trong bộ vá (php7.4-imagick, php8.x... giữ nguyên)
ours=$(zcat "$REPO_DIR/Packages.gz" | awk '/^Package:/{print $2}' | sort -u)
installed=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1=="ii"{print $2}' | sort -u)
pkgs=$(comm -12 <(echo "$ours") <(echo "$installed"))

echo "== 3. Sao lưu gói đang cài (PPA ondrej đã xoá bản cũ, apt không hạ version được)"
BACKUP_DIR=/opt/php2shell-bionic-backup/$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
apt-get install -y -qq dpkg-repack >/dev/null
# shellcheck disable=SC2086
(cd "$BACKUP_DIR" && dpkg-repack $pkgs >/dev/null 2>&1)
ls "$BACKUP_DIR"/*.deb | wc -l | xargs -I{} echo "   {} gói đã sao lưu vào $BACKUP_DIR"
[ "$(ls "$BACKUP_DIR"/*.deb | wc -l)" -eq "$(echo "$pkgs" | wc -l)" ] || { echo "Sao lưu thiếu gói, dừng." >&2; exit 1; }

echo "== 4. Nâng các gói php7.4 đã cài"
echo "   $(echo "$pkgs" | wc -l) gói: $(echo $pkgs)"
newver=$(zcat "$REPO_DIR/Packages.gz" | awk '/^Package: php7.4-common$/{f=1} f&&/^Version:/{print $2; exit}')
# Gắn đúng version để apt không chọn bản khác; -o Dpkg::Options giữ nguyên file cấu hình đã sửa
# shellcheck disable=SC2046
apt-get install -y --only-upgrade -o Dpkg::Options::=--force-confold \
  $(for p in $pkgs; do echo "$p=$newver"; done)

echo "== 5. Kiểm chứng"
bad=""
for p in $pkgs; do
  v=$(dpkg-query -W -f='${Version}' "$p")
  echo "   $p $v"
  [ "$v" = "$newver" ] || bad="$bad $p"
done
if [ -n "$bad" ]; then
  echo "Còn gói chưa phải bản vá:$bad" >&2; exit 1
fi
grep -c zend_new_array_singleton /usr/bin/php7.4 >/dev/null && echo "   /usr/bin/php7.4 có code vá"

cat <<'EOF'

Xong. Còn phải restart để nạp binary mới:
  sudo apache2ctl configtest && sudo systemctl restart apache2   # mod_php
  sudo systemctl restart php7.4-fpm                              # nếu service php7.4-fpm đang chạy
  sudo supervisorctl restart all                                 # queue worker (artisan queue:work)
Tuỳ chọn, ghim phiên bản:
  sudo apt-mark hold $(dpkg-query -W -f='${Package}\n' 'php7.4*' 'libapache2-mod-php7.4' 2>/dev/null)
EOF
