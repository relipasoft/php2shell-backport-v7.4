#!/usr/bin/env bash
# Build php7.4 for Ubuntu 18.04 (bionic) from the ondrej/php PPA packaging (source 1:7.4.33-31, jammy upload),
# using ondrej patches 0001–0135 plus the PHP2Shell patch from upstream php-src
# (commit 712e60f9ed, branch PHP-7.4-CVE-2026-109618-109619) instead of ondrej patch 0164.
# Run INSIDE an ubuntu:18.04 container:
#   docker run --rm -v "$PWD":/kit:ro -v "$PWD/out":/out ubuntu:18.04 bash /kit/build-deb.sh
# Output: .deb files in ./out/ + apt index (Packages.gz), version = 1:7.4.33-31~ubuntu18.04.1<BUILDID>
set -euo pipefail
KIT=${KIT:-/kit}
OUT=${OUT:-/out}
BUILDID=${BUILDID:-+relipa.php2shell.1}
SRC_VER=7.4.33-31+ubuntu22.04.1+deb.sury.org+1
POOL=https://ppa.launchpadcontent.net/ondrej/php/ubuntu/pool/main/p/php7.4
# Key that signs the .dsc upload: "Ondřej Surý (Automated PPA Upload Key)", registered on the Launchpad account ~ondrej
# (https://api.launchpad.net/1.0/~ondrej/gpg_keys)
ONDREJ_KEY=6A1AAD7AE5B401C6E259A7B257067BAA1314C7FC
# sha256 of php-7.4.33.tar.xz per https://www.php.net/releases/index.php?json&version=7.4.33
TARBALL_SHA256=924846abf93bc613815c55dd3f5809377813ac62a9ec4eb3778675b82a27b927
# Last ondrej patch kept. Patch 0136 (GHSA-m8rr-4c36-8gq4) changes the isspace() lines right next to the lines
# the PHP2Shell patch changes in main/rfc1867.c, so from 0136 on the upstream patch does not apply verbatim.
LAST_ONDREJ_PATCH=135
export DEBIAN_FRONTEND=noninteractive

echo "== 1. Install build tools"
apt-get update -qq
apt-get install -y -qq build-essential devscripts equivs fakeroot curl ca-certificates gnupg dpkg-dev quilt >/dev/null

echo "== 2. Download the ondrej source package and verify its signature"
mkdir -p /build && cd /build
fetch() { curl -fsSL -o "$1" "$POOL/$(echo "$1" | sed 's/+/%2B/g')"; }
fetch "php7.4_${SRC_VER}.dsc"
# Download every file listed in the Files section of the .dsc (orig.tar.xz, orig.tar.xz.asc, debian.tar.xz)
for f in $(awk '/^Files:/{f=1;next} /^[^ ]/{f=0} f{print $3}' "php7.4_${SRC_VER}.dsc"); do fetch "$f"; done
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${ONDREJ_KEY}" | gpg --batch --quiet --import
gpg --batch --verify "php7.4_${SRC_VER}.dsc"
echo "$TARBALL_SHA256  php7.4_7.4.33.orig.tar.xz" | sha256sum -c -
# --skip-patches: do not apply patches yet so the series can be edited first; file checksums are still checked against the .dsc
dpkg-source -x --skip-patches "php7.4_${SRC_VER}.dsc" php7.4-7.4.33 >/dev/null
cd php7.4-7.4.33

echo "== 3. Replace patches: keep ondrej 0001–0$LAST_ONDREJ_PATCH, add the PHP2Shell patch from php-src"
awk -F- -v last="$LAST_ONDREJ_PATCH" '{n=$1+0} n>=1 && n<=last' debian/patches/series > debian/patches/series.new
dropped=$(grep -vxFf debian/patches/series.new debian/patches/series || true)
echo "$dropped" | while read -r p; do [ -n "$p" ] && rm -f "debian/patches/$p"; done
echo "   dropped $(echo "$dropped" | grep -c .) patches: $(echo "$dropped" | head -1) ... $(echo "$dropped" | tail -1)"
cp "$KIT/php-7.4.33-php2shell.patch" debian/patches/
echo php-7.4.33-php2shell.patch >> debian/patches/series.new
mv debian/patches/series.new debian/patches/series
# Apply the whole series; the PHP2Shell patch must apply with fuzz 0
QUILT_PATCHES=debian/patches quilt push -a -q --fuzz=0 >/tmp/quilt.log 2>&1 || { tail -20 /tmp/quilt.log; exit 1; }
tail -1 /tmp/quilt.log
QUILT_PATCHES=debian/patches quilt pop -a -q >/dev/null

echo "== 4. Add a changelog entry for bionic"
NEWVER="1:7.4.33-31~ubuntu18.04.1${BUILDID}"
{ printf 'php7.4 (%s) bionic; urgency=high\n\n  * Build for Ubuntu 18.04 (bionic) from ondrej/php packaging %s,\n    keeping ondrej patches 0001-0%s only (0136-0164 dropped).\n  * Add php-7.4.33-php2shell.patch from php-src commit 712e60f9ed\n    (branch PHP-7.4-CVE-2026-109618-109619), minus 4 hunks already in\n    0062-Introduce-max_multipart_body_parts-INI.patch:\n    CVE-2026-109618 (GHSA-w8hw-w9fx-j79w), CVE-2026-109619 (GHSA-6wmf-4rv5-p3rp).\n\n -- Internal rebuild <devops@example.com>  %s\n\n' \
    "$NEWVER" "$SRC_VER" "$LAST_ONDREJ_PATCH" "$(date -R)"; cat debian/changelog; } > debian/changelog.new
mv debian/changelog.new debian/changelog
head -1 debian/changelog

echo "== 5. Install build dependencies"
mk-build-deps -ir -t 'apt-get -y -qq --no-install-recommends' debian/control >/dev/null
rm -f php7.4-build-deps_*

echo "== 6. Build (test suite skipped)"
DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -uc -us > /tmp/build.log 2>&1 \
  || { tail -60 /tmp/build.log; exit 1; }

echo "== 7. Output"
cd /build
cp ./*.deb "$OUT/"
cp php7.4-7.4.33/debian/patches/series "$OUT/patches-series.txt"
cd "$OUT" && dpkg-scanpackages -m . /dev/null 2>/dev/null > Packages && gzip -9kf Packages && sha256sum ./*.deb > SHA256SUMS
ls ./*.deb | wc -l
dpkg-deb -f "$(ls php7.4-common_*.deb)" Package Version Depends | head -5
