#!/usr/bin/env bash
# Upgrade php7.4 (ondrej PPA) to the build patched for PHP2Shell (CVE-2026-109618, CVE-2026-109619) on Ubuntu 18.04.
#
#   sudo bash install.sh <out/ directory>
#
# The script only copies the .deb files to /opt/php2shell-bionic, adds one local apt source and upgrades the installed php7.4 packages.
# It installs no new extensions, removes no packages and restarts no services.
set -euo pipefail

SRC_DIR="${1:?Usage: sudo bash install.sh <directory containing the .deb files and Packages.gz>}"
REPO_DIR=/opt/php2shell-bionic
LIST_FILE=/etc/apt/sources.list.d/relipa-php2shell.list
export DEBIAN_FRONTEND=noninteractive

if ! grep -q 'VERSION_CODENAME=bionic' /etc/os-release 2>/dev/null; then
  echo "For Ubuntu 18.04 (bionic) only." >&2; exit 1
fi
if ! dpkg-query -W -f='${Status} ${Version}\n' php7.4-common 2>/dev/null | grep -q '^install ok installed 1\?:\?7\.4\.'; then
  echo "php7.4-common is not installed on this host. This script only upgrades, it does not install." >&2; exit 1
fi
if [ ! -f "$SRC_DIR/Packages.gz" ]; then
  echo "$SRC_DIR/Packages.gz not found." >&2; exit 1
fi

echo "== 0. Current php packages"
dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\n' 'php*' 'libapache2-mod-php*' 2>/dev/null | awk '$1=="ii"{print $2, $3}'

echo "== 1. Copy .deb files to $REPO_DIR"
mkdir -p "$REPO_DIR"
cp -r "$SRC_DIR"/. "$REPO_DIR"/
(cd "$REPO_DIR" && sha256sum -c --quiet SHA256SUMS)

echo "== 2. Add the local apt source"
echo "deb [trusted=yes] file:$REPO_DIR ./" > "$LIST_FILE"
apt-get update -qq -o Dir::Etc::sourcelist="$LIST_FILE" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
# Refresh the Ubuntu index so missing libraries can be installed (libicu60, libonig4, libargon2-0...)
apt-get update -qq || echo "   (warning: apt-get update failed for another source, continuing)"

# Only packages that are installed AND in the patched set (php7.4-imagick, php8.x... are left as is)
ours=$(zcat "$REPO_DIR/Packages.gz" | awk '/^Package:/{print $2}' | sort -u)
installed=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1=="ii"{print $2}' | sort -u)
pkgs=$(comm -12 <(echo "$ours") <(echo "$installed"))

echo "== 3. Back up installed packages (the ondrej PPA removed the old versions, apt cannot downgrade)"
BACKUP_DIR=/opt/php2shell-bionic-backup/$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
apt-get install -y -qq dpkg-repack >/dev/null
# shellcheck disable=SC2086
(cd "$BACKUP_DIR" && dpkg-repack $pkgs >/dev/null 2>&1)
ls "$BACKUP_DIR"/*.deb | wc -l | xargs -I{} echo "   {} packages backed up to $BACKUP_DIR"
[ "$(ls "$BACKUP_DIR"/*.deb | wc -l)" -eq "$(echo "$pkgs" | wc -l)" ] || { echo "Backup is missing packages, stopping." >&2; exit 1; }

echo "== 4. Upgrade the installed php7.4 packages"
echo "   $(echo "$pkgs" | wc -l) packages: $(echo $pkgs)"
newver=$(zcat "$REPO_DIR/Packages.gz" | awk '/^Package: php7.4-common$/{f=1} f&&/^Version:/{print $2; exit}')
# Pin the exact version so apt picks no other build; -o Dpkg::Options keeps modified config files
# shellcheck disable=SC2046
apt-get install -y --only-upgrade -o Dpkg::Options::=--force-confold \
  $(for p in $pkgs; do echo "$p=$newver"; done)

echo "== 5. Verify"
bad=""
for p in $pkgs; do
  v=$(dpkg-query -W -f='${Version}' "$p")
  echo "   $p $v"
  [ "$v" = "$newver" ] || bad="$bad $p"
done
if [ -n "$bad" ]; then
  echo "Packages not on the patched build:$bad" >&2; exit 1
fi
grep -c zend_new_array_singleton /usr/bin/php7.4 >/dev/null && echo "   /usr/bin/php7.4 contains the fix"

cat <<'EOF'

Done. Restart services to load the new binaries:
  sudo apache2ctl configtest && sudo systemctl restart apache2   # mod_php
  sudo systemctl restart php7.4-fpm                              # if php7.4-fpm is running
  sudo supervisorctl restart all                                 # queue worker (artisan queue:work)
Optional, pin the versions:
  sudo apt-mark hold $(dpkg-query -W -f='${Package}\n' 'php7.4*' 'libapache2-mod-php7.4' 2>/dev/null)
EOF
