# php2shell-backport-v7.4

`php7.4` packages for **Ubuntu 18.04 (bionic)** that replace the packages installed from the ondrej PPA (`ppa:ondrej/php`). They add the PHP2Shell fix for **CVE-2026-109618** and **CVE-2026-109619** (both Critical, remote code execution). The fix comes from upstream php-src: commit `712e60f9ed` on branch `PHP-7.4-CVE-2026-109618-109619`.

The ondrej PPA no longer builds for Ubuntu 18.04 and has removed all bionic packages. There is no other official fix for `php7.4` on 18.04.

> Unofficial build. Not affiliated with or endorsed by The PHP Group, Zend or Ondřej Surý. See `NOTICE` and `LICENSE`.

## Scope

For Ubuntu 18.04 servers running `php7.4` from the ondrej PPA (`apache2` mod_php and/or `php7.4-fpm`, CLI, queue workers). One package set works for every server. Roll out **develop → staging → prod**, and move to the next server only after the application (web, API, cron, queue) runs normally on the previous one.

**Take an AMI or snapshot before installing on each server.** The ondrej PPA has removed `7.4.27`/`7.4.29`, so `apt` cannot downgrade. `install.sh` backs up the installed packages (see Rollback), but a snapshot is still the most reliable way back.

## Repository contents

```text
php2shell-backport-v7.4/
├── README.md                              # this document
├── LICENSE                                # license (BSD-3-Clause / PHP License v4), plus the original 3.01 and Zend 2.00 texts
├── NOTICE                                 # attribution, unofficial-build statement
├── install.sh                             # install script for the server
├── build-deb.sh                           # build script (only needed to rebuild)
├── php-7.4.33-php2shell.patch             # patch used for the build (php-src commit minus 4 hunks ondrej already has)
├── php-7.4.33-php2shell.upstream.patch    # original patch of commit 712e60f9ed
├── strip_hunks.py                         # derives the build patch from the original patch
├── source/                                # corresponding source of the .deb packages (php.net tarball + ondrej source package)
└── out/
    ├── *_7.4.33-31~ubuntu18.04.1+relipa.php2shell.1_*.deb   # 38 patched php7.4 packages
    ├── Packages, Packages.gz              # apt index
    ├── SHA256SUMS                         # checksums of the .deb files
    └── patches-series.txt                 # patches applied in the build
```

`install.sh` only **upgrades the `php7.4*` and `libapache2-mod-php7.4` packages already installed** on the server. It installs no new extensions, removes no packages and does not change Apache modules. These packages are left untouched:

- `php7.4-imagick`: built separately; still works because the PHP 7.4 ABI (`20190902`) does not change.
- `php8.0-*`, `php8.1-*`, `php-common`, `php-gd`, `php-xml`, `php-pear`, `libapache2-mod-php` (meta).

## Step 1. Get the repository (on your machine)

```bash
git clone https://github.com/relipasoft/php2shell-backport-v7.4.git
cd php2shell-backport-v7.4

# Check the .deb files; every line must say "OK"
(cd out && sha256sum -c SHA256SUMS)
```

On macOS, use `shasum -a 256` instead of `sha256sum`.

## Step 2. Check the server before installing

```bash
ssh -i ~/.ssh/<key>.pem ubuntu@<server-ip>
```

```bash
lsb_release -ds                    # must be: Ubuntu 18.04.6 LTS
dpkg-query -W php7.4-common        # must be: php7.4-common  7.4.27-1+ubuntu18.04.1+deb.sury.org+1 (or 7.4.29-...)
df -h /opt                         # about 200 MB free needed
```

If `php7.4-common` is missing or the OS is not 18.04, **stop** and send the output to your administrator.

Record the current state to compare after the install:

```bash
php7.4 -m > ~/php-modules-before.txt
sudo supervisorctl status          # note the queue worker program names
systemctl is-active apache2 php7.4-fpm
```

Log out of the server (`exit`).

## Step 3. Copy the packages to the server (on your machine)

Run in the `php2shell-backport-v7.4` directory:

```bash
ssh -i ~/.ssh/<key>.pem ubuntu@<server-ip> 'mkdir -p /tmp/php2shell'
scp -i ~/.ssh/<key>.pem -r out/ install.sh ubuntu@<server-ip>:/tmp/php2shell/
```

## Step 4. Install on the server

```bash
ssh -i ~/.ssh/<key>.pem ubuntu@<server-ip>
sudo bash /tmp/php2shell/install.sh /tmp/php2shell/out
```

The script:

1. Lists the PHP packages currently installed.
2. Copies the `.deb` files to `/opt/php2shell-bionic` and checks `SHA256SUMS`.
3. Adds the local apt source `/etc/apt/sources.list.d/relipa-php2shell.list` and runs `apt-get update`.
4. **Backs up** the installed `php7.4*` packages with `dpkg-repack` to `/opt/php2shell-bionic-backup/<date-time>/`.
5. Upgrades the installed `php7.4*` packages to the patched build and keeps modified config files (`--force-confold`).
6. Verifies the result. If any package is not on the patched build, it reports an error and exits with code 1.

The script does **not** restart services. Config files (`/etc/php/7.4/apache2/php.ini`, `/etc/php/7.4/cli/php.ini`, `/etc/php/7.4/fpm/...`, `conf.d/`) are kept as they are.

`apt` may install a few standard Ubuntu 18.04 libraries the new packages need: `libicu60`, `libonig4`, `libargon2-0`. They do not conflict with the ondrej libraries already installed (`libicu65`, `libargon2-1`, ...).

## Step 5. Restart

```bash
sudo apache2ctl configtest                 # must print "Syntax OK"
sudo systemctl restart apache2

sudo systemctl restart php7.4-fpm          # only on servers where php7.4-fpm is running

sudo supervisorctl restart all             # queue workers (artisan queue:work)
```

**Restarting the queue workers is required.** Workers are long-running processes and keep the old, unpatched PHP in memory until restarted. If supervisor manages several programs and you do not want to restart all of them, restart only the programs running `artisan queue:work` (names from `supervisorctl status` in step 2).

Cron (`schedule:run`) needs nothing: each run starts the new PHP.

## Step 6. Check after installing

```bash
dpkg -l | awk '/^ii/ && /php7.4|libapache2-mod-php7.4/ {print $2, $3}'
```

All `php7.4*` packages (except `php7.4-imagick`) and `libapache2-mod-php7.4` must show version `1:7.4.33-31~ubuntu18.04.1+relipa.php2shell.1`.

```bash
php7.4 -v | head -1                                                    # PHP 7.4.33
grep -c zend_new_array_singleton /usr/bin/php7.4                       # must print 1 (function exists only in the patched build)
grep -c zend_new_array_singleton /usr/lib/apache2/modules/libphp7.4.so  # must print 1
php7.4 -m | diff ~/php-modules-before.txt - && echo "same extensions as before"
sudo apache2ctl -M 2>/dev/null | grep php                              # php7_module (shared)
sudo supervisorctl status                                              # workers RUNNING, uptime just reset
```

Then test the application: call a few APIs, open the main pages, push a test job to the queue, and check the Laravel log (`storage/logs`) and the Apache log (`/var/log/apache2/error.log`).

You can remove the temporary directory: `rm -rf /tmp/php2shell`. Do **not** remove `/opt/php2shell-bionic` or `/opt/php2shell-bionic-backup`.

### Testing notes

- PHP moves from `7.4.27`/`7.4.29` to `7.4.33`. These are bug-fix releases within the 7.4 branch and normally do not affect application code.
- The `intl` extension uses Ubuntu's `libicu60` instead of ondrej's `libicu65`. If the application formats dates, numbers or currency with `intl` (for example `IntlDateFormatter`, `NumberFormatter`), check those screens on develop.

## Pinning the version (recommended on prod)

```bash
sudo apt-mark hold $(dpkg-query -W -f='${Package}\n' 'php7.4*' 'libapache2-mod-php7.4' 2>/dev/null)
```

## Rollback

**Option 1: restore the AMI/snapshot** taken before the install.

**Option 2: reinstall the packages backed up** in step 4:

```bash
sudo apt-mark unhold $(dpkg-query -W -f='${Package}\n' 'php7.4*' 'libapache2-mod-php7.4' 2>/dev/null)   # if pinned
ls /opt/php2shell-bionic-backup/                     # pick a backup directory
sudo rm -f /etc/apt/sources.list.d/relipa-php2shell.list
sudo dpkg -i /opt/php2shell-bionic-backup/<date-time>/*.deb
sudo apache2ctl configtest && sudo systemctl restart apache2
sudo systemctl restart php7.4-fpm                    # if present
sudo supervisorctl restart all
dpkg-query -W php7.4-common                          # back to 7.4.27 or 7.4.29
```

Rollback returns the server to the **unpatched** version. Tell your administrator right away if you have to roll back.

## Two behavior changes (intended, same as PHP's fix)

- When a request exceeds `memory_limit`, or a memory allocation size overflows, the process **exits** instead of trying to recover. Apache starts a new process for the next request. Code that catches `Allowed memory size exhausted` and carries on will behave differently.
- `session.upload_progress` is disabled in code, even though `php -i` still shows `On`.

## Troubleshooting

`install.sh` prints its messages in Vietnamese; the English meaning is in parentheses.

| Message | Cause and action |
| --- | --- |
| `Chỉ dành cho Ubuntu 18.04 (bionic).` (Ubuntu 18.04 only) | The server is not 18.04. Do not install. |
| `Máy này chưa cài php7.4-common.` (php7.4-common is not installed) | The server does not use php7.4. Do not install. |
| `Không thấy .../Packages.gz` (Packages.gz not found) | Wrong path in step 4, or files missing from the copy. Check `ls /tmp/php2shell/out`. |
| `sha256sum` reports `FAILED` | A file was damaged during download or copy. Clone the repository again. |
| `Sao lưu thiếu gói, dừng.` (backup incomplete, stopping) | `dpkg-repack` did not back up every package. Nothing has changed yet. Send the output to your administrator. |
| `apt-get` reports `unmet dependencies` | The server is missing libraries and cannot download them from the Ubuntu repositories. Check `sudo apt-get update`. Send the full output; do not run `--fix-broken` without asking. |
| `apache2ctl configtest` fails | Check `/var/log/apache2/error.log`. Roll back if needed. |

## Patch details

| | |
| --- | --- |
| Fix | Commit [`712e60f9ed`](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2) "Avoid state corruption via bailout" by the PHP security team, on branch [`PHP-7.4-CVE-2026-109618-109619`](https://github.com/php/php-src/tree/PHP-7.4-CVE-2026-109618-109619). 17 files, 78 hunks |
| Build patch | `php-7.4.33-php2shell.patch` = the commit above without 4 hunks (`main/main.c` hunk 1, `main/rfc1867.c` hunks 5–7) that already exist verbatim in ondrej patch `0062-Introduce-max_multipart_body_parts-INI.patch`. Applied with `--fuzz=0` |
| Verification | On the final source tree, reverse-applying the original commit `712e60f9ed` (dry run, fuzz 0) succeeds for all 78/78 hunks, so every change of the commit is present |
| Rest of the branch | Apart from the fix, the branch differs from the 7.4.33 tarball only by commit `004cb82750` "Bumb versions" (`NEWS` and `AC_INIT` in `configure.ac` set to `7.4.34-dev`). It is not code and is not included |
| PHP tarball | `php7.4_7.4.33.orig.tar.xz` from the ondrej PPA; its sha256 matches `php-7.4.33.tar.xz` from php.net |
| Packaging | `debian/` from the ondrej source package `php7.4 1:7.4.33-31+ubuntu22.04.1+deb.sury.org+1`. The `.dsc` signature is checked against "Ondřej Surý (Automated PPA Upload Key)" `6A1AAD7AE5B401C6E259A7B257067BAA1314C7FC`, registered on the Launchpad account `~ondrej` |
| ondrej patches kept | `0001`–`0135`: Debian packaging patches and the security fixes ondrej backported up to early May 2026. Full list in `out/patches-series.txt` |
| ondrej patches dropped | `0136`–`0164` (29 patches). `0136` (GHSA-m8rr-4c36-8gq4) changes the `isspace()` lines right next to the lines the fix changes in `main/rfc1867.c`, so from `0136` on the upstream commit does not apply verbatim. The dropped patches include many security fixes ondrej released from May to October 2026 (openssl, pgsql, phar, soap, mysqlnd, FastCGI, ...) and `0164` (ondrej's own adaptation of the same fix) |
| Build | `ubuntu:18.04` container; build dependencies from the Ubuntu 18.04 repositories (the ondrej PPA bionic index is empty) |
| Version | `1:7.4.33-31~ubuntu18.04.1+relipa.php2shell.1`: higher than ondrej's `7.4.27`/`7.4.29`, lower than ondrej's full `1:7.4.33-31` |
| Architecture | `amd64` |
| Signing | Packages are not signed. The apt source uses `[trusted=yes]`; integrity is checked with `SHA256SUMS` |

### Test results (2026-10-22, `ubuntu:18.04` container)

The ondrej PPA no longer has `7.4.29`, so the test used the built packages repackaged as version `7.4.29-1+ubuntu18.04.1+deb.sury.org+1`, with ondrej's `php-common 2:101`. This tests the `apt` upgrade path (dependencies, conffiles, maintainer scripts, Apache module), not code differences between 7.4.29 and 7.4.33.

| Check | Result |
| --- | --- |
| `install.sh` on a host with 17 packages (`apache2` + mod_php, `php7.4-fpm`) | All 17 packages upgraded, self-check passed |
| `php7.4 -m` before and after | Identical |
| `apache2ctl configtest`, `apache2ctl -M` | `Syntax OK`, `php7_module` loaded |
| `php-fpm7.4 -t` | `test is successful` |
| Fix present in binaries | `zend_new_array_singleton` found in `php7.4`, `libphp7.4.so`, `php-fpm7.4` |
| Conffiles | No `.dpkg-dist`/`.dpkg-old`, configuration unchanged |
| Extra libraries installed | `libargon2-0`, `libicu60`, `libonig4` from the Ubuntu repositories |
| Backup in `install.sh` | 17/17 packages saved to `/opt/php2shell-bionic-backup/<date-time>/` |
| Rollback as documented (option 2) | `dpkg -i` returned all 17 packages to `7.4.29-1+ubuntu18.04.1+deb.sury.org+1`, `apache2ctl configtest` passed |

## Rebuilding (for maintainers)

```bash
mkdir -p out
docker run --rm -e BUILDID=+relipa.php2shell.1 -v "$PWD":/kit:ro -v "$PWD/out":/out ubuntu:18.04 bash /kit/build-deb.sh
```

Takes about 20–25 minutes. For a new release, bump `BUILDID` (for example `+relipa.php2shell.2`) so `apt` picks it up.

## Notes

- PHP describes this patch as a "minimal mitigation". These packages do **not** include the ondrej security fixes from patch `0136` onward.
- Ubuntu 18.04 is out of standard support and PHP 7.4 has been end-of-life since November 2022. In the long term, move to a supported OS and PHP version.

## License and attribution

This product includes PHP software, freely available from <http://www.php.net/software/>.
This product includes the Zend Engine, freely available at http://www.zend.com

- Repository scripts and documentation (`build-deb.sh`, `install.sh`, `strip_hunks.py`, README, NOTICE): BSD-3-Clause, © 2026 Relipa.
- PHP code (the two patch files, `out/*.deb`, `source/`): PHP 7.4.33 was released under the PHP License 3.01 and the Zend Engine License 2.00. This repository uses that code under the PHP License v4 and the Zend Engine License v3.0 (equivalent to BSD-3-Clause), as allowed by clause 5 of the PHP License 3.01 and clause 4 of the Zend Engine License 2.00. See [php.net/license](https://www.php.net/license/).
- Other components in the `.deb` packages (bundled libraries, some under LGPL; Debian packaging by Ondřej Surý) keep their own licenses, listed in `/usr/share/doc/php7.4-common/copyright` inside the packages. Do not remove this file when redistributing.
- The corresponding source of the `.deb` packages is in `source/` (checksums in `source/SHA256SUMS`) and can be rebuilt with `build-deb.sh`.
- Unofficial build. Not affiliated with or endorsed by The PHP Group, Zend, Perforce or Ondřej Surý.

## References

- [Ubuntu – CVE-2026-109618](https://ubuntu.com/security/CVE-2026-109618)
- [Ubuntu – CVE-2026-109619](https://ubuntu.com/security/CVE-2026-109619)
- [php-src commit 712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2)
- [php-src branch PHP-7.4-CVE-2026-109618-109619](https://github.com/php/php-src/tree/PHP-7.4-CVE-2026-109618-109619)
- [PPA ondrej/php](https://launchpad.net/~ondrej/+archive/ubuntu/php)
