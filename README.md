# php2shell-backport-v7.4

Gói `php7.4` cho **Ubuntu 18.04 (bionic)**, thay thế bản cài từ PPA ondrej (`ppa:ondrej/php`). Gói thêm bản vá PHP2Shell cho **CVE-2026-109618** và **CVE-2026-109619** (cả hai mức Critical, cho phép remote code execution). Code vá lấy từ php-src chính chủ: commit `712e60f9ed` trên branch `PHP-7.4-CVE-2026-109618-109619`.

PPA ondrej đã ngừng build cho Ubuntu 18.04 và đã xoá toàn bộ gói bionic. Không còn bản vá chính thức nào cho `php7.4` trên 18.04.

> Bản build không chính thức, không liên kết với hay được The PHP Group, Zend hoặc Ondřej Surý xác nhận. Xem `NOTICE` và `LICENSE`.

## Phạm vi

Dành cho server Ubuntu 18.04 đang chạy `php7.4` cài từ PPA ondrej (`apache2` mod_php và/hoặc `php7.4-fpm`, CLI, queue worker). Một bộ gói dùng chung cho mọi server. Nên triển khai lần lượt **develop → staging → prod**, chỉ chuyển sang server tiếp theo khi ứng dụng (web, API, cron, queue) ở server trước chạy bình thường.

**Tạo AMI hoặc snapshot trước khi cài trên mỗi server.** PPA ondrej đã xoá bản `7.4.27`/`7.4.29`, nên `apt` không thể hạ về bản cũ. `install.sh` có tự sao lưu các gói đang cài (xem phần Rollback), nhưng snapshot vẫn là cách khôi phục chắc chắn nhất.

## Nội dung repo

```text
php2shell-backport-v7.4/
├── README.md                              # tài liệu này
├── LICENSE                                # giấy phép (BSD-3-Clause / PHP License v4), kèm bản gốc 3.01 và Zend 2.00
├── NOTICE                                 # ghi công, tuyên bố không chính thức
├── install.sh                             # script cài trên server
├── build-deb.sh                           # script build (chỉ cần khi build lại)
├── php-7.4.33-php2shell.patch             # patch dùng khi build (commit php-src, bỏ 4 hunk ondrej có sẵn)
├── php-7.4.33-php2shell.upstream.patch    # patch gốc của commit 712e60f9ed
├── strip_hunks.py                         # tạo patch dùng khi build từ patch gốc
├── source/                                # mã nguồn tương ứng với các gói .deb (tarball php.net + source package ondrej)
└── out/
    ├── *_7.4.33-31~ubuntu18.04.1+relipa.php2shell.1_*.deb   # 38 gói php7.4 đã vá
    ├── Packages, Packages.gz              # index apt
    ├── SHA256SUMS                         # checksum các file .deb
    └── patches-series.txt                 # danh sách patch đã áp khi build
```

`install.sh` chỉ **nâng các gói `php7.4*` và `libapache2-mod-php7.4` đã cài sẵn** trên server. Script không cài thêm extension, không gỡ gói nào, không đổi module Apache. Các gói sau được giữ nguyên:

- `php7.4-imagick`: build riêng, vẫn chạy được vì ABI của PHP 7.4 (`20190902`) không đổi.
- Các gói `php8.0-*`, `php8.1-*`, `php-common`, `php-gd`, `php-xml`, `php-pear`, `libapache2-mod-php` (meta).

## Bước 1. Tải repo (trên máy của bạn)

```bash
git clone https://github.com/relipasoft/php2shell-backport-v7.4.git
cd php2shell-backport-v7.4

# Kiểm tra toàn vẹn các file .deb, mọi dòng phải là "OK"
(cd out && sha256sum -c SHA256SUMS)
```

Trên macOS, thay `sha256sum` bằng `shasum -a 256`.

## Bước 2. Kiểm tra server trước khi cài

```bash
ssh -i ~/.ssh/<key>.pem ubuntu@<server-ip>
```

```bash
lsb_release -ds                    # phải là: Ubuntu 18.04.6 LTS
dpkg-query -W php7.4-common        # phải là: php7.4-common  7.4.27-1+ubuntu18.04.1+deb.sury.org+1 (hoặc 7.4.29-...)
df -h /opt                         # cần trống khoảng 200 MB
```

Nếu `php7.4-common` không có, hoặc OS không phải 18.04, thì **dừng lại** và gửi output cho người phụ trách.

Lưu lại trạng thái hiện tại để đối chiếu sau khi cài:

```bash
php7.4 -m > ~/php-modules-before.txt
sudo supervisorctl status          # ghi lại tên program của queue worker
systemctl is-active apache2 php7.4-fpm
```

Thoát khỏi server (`exit`).

## Bước 3. Copy gói lên server (trên máy của bạn)

Chạy trong thư mục `php2shell-backport-v7.4`:

```bash
ssh -i ~/.ssh/<key>.pem ubuntu@<server-ip> 'mkdir -p /tmp/php2shell'
scp -i ~/.ssh/<key>.pem -r out/ install.sh ubuntu@<server-ip>:/tmp/php2shell/
```

## Bước 4. Cài trên server

```bash
ssh -i ~/.ssh/<key>.pem ubuntu@<server-ip>
sudo bash /tmp/php2shell/install.sh /tmp/php2shell/out
```

Script làm các việc sau:

1. In danh sách gói PHP hiện tại.
2. Chép `.deb` vào `/opt/php2shell-bionic` và kiểm tra `SHA256SUMS`.
3. Thêm nguồn apt local `/etc/apt/sources.list.d/relipa-php2shell.list`, rồi chạy `apt-get update`.
4. **Sao lưu** các gói `php7.4*` đang cài bằng `dpkg-repack` vào `/opt/php2shell-bionic-backup/<ngày-giờ>/`.
5. Nâng các gói `php7.4*` đang cài lên bản vá, giữ nguyên file cấu hình đã sửa (`--force-confold`).
6. Tự kiểm tra kết quả. Nếu còn gói chưa lên bản vá, script báo lỗi và thoát với mã 1.

Script **không** restart service. File cấu hình (`/etc/php/7.4/apache2/php.ini`, `/etc/php/7.4/cli/php.ini`, `/etc/php/7.4/fpm/...`, `conf.d/`) được giữ nguyên.

`apt` có thể cài thêm vài thư viện chuẩn của Ubuntu 18.04 mà gói mới cần: `libicu60`, `libonig4`, `libargon2-0`. Các thư viện này không xung đột với thư viện của ondrej đang có (`libicu65`, `libargon2-1`...).

## Bước 5. Restart

```bash
sudo apache2ctl configtest                 # phải ra "Syntax OK"
sudo systemctl restart apache2

sudo systemctl restart php7.4-fpm          # chỉ trên server có php7.4-fpm đang chạy (prod)

sudo supervisorctl restart all             # queue worker (artisan queue:work)
```

**Bắt buộc restart queue worker.** Worker là process chạy liên tục, nên vẫn giữ PHP cũ chưa vá trong bộ nhớ cho tới khi restart. Nếu supervisor quản lý nhiều program và không muốn restart tất cả, chỉ restart program chạy `artisan queue:work` (tên lấy từ `supervisorctl status` ở bước 2).

Cron (`schedule:run`) không cần làm gì: mỗi lần chạy, cron tự khởi động PHP mới.

## Bước 6. Kiểm tra sau khi cài

```bash
dpkg -l | awk '/^ii/ && /php7.4|libapache2-mod-php7.4/ {print $2, $3}'
```

Các gói `php7.4*` (trừ `php7.4-imagick`) và `libapache2-mod-php7.4` phải có version `1:7.4.33-31~ubuntu18.04.1+relipa.php2shell.1`.

```bash
php7.4 -v | head -1                                                    # PHP 7.4.33
grep -c zend_new_array_singleton /usr/bin/php7.4                       # phải ra 1 (hàm chỉ có trong bản vá)
grep -c zend_new_array_singleton /usr/lib/apache2/modules/libphp7.4.so  # phải ra 1
php7.4 -m | diff ~/php-modules-before.txt - && echo "extension giống trước"
sudo apache2ctl -M 2>/dev/null | grep php                              # php7_module (shared)
sudo supervisorctl status                                              # worker RUNNING, uptime vừa reset
```

Sau đó kiểm tra ứng dụng: gọi vài API, mở các trang chính, đẩy thử một job vào queue, xem log Laravel (`storage/logs`) và Apache (`/var/log/apache2/error.log`).

Có thể dọn thư mục tạm: `rm -rf /tmp/php2shell`. **Không** xoá `/opt/php2shell-bionic` và `/opt/php2shell-bionic-backup`.

### Lưu ý khi test

- PHP lên từ `7.4.27`/`7.4.29` tới `7.4.33`. Đây vẫn là các bản sửa lỗi trong cùng nhánh 7.4, thường không ảnh hưởng code.
- Extension `intl` dùng `libicu60` của Ubuntu thay vì `libicu65` của ondrej. Nếu ứng dụng định dạng ngày, số hoặc tiền tệ bằng `intl` (ví dụ `IntlDateFormatter`, `NumberFormatter`), hãy kiểm tra các màn hình đó trên develop.

## Ghim phiên bản (khuyên dùng trên prod)

```bash
sudo apt-mark hold $(dpkg-query -W -f='${Package}\n' 'php7.4*' 'libapache2-mod-php7.4' 2>/dev/null)
```

## Rollback

**Cách 1: khôi phục AMI/snapshot** đã tạo trước khi cài.

**Cách 2: cài lại các gói đã sao lưu** ở bước 4:

```bash
sudo apt-mark unhold $(dpkg-query -W -f='${Package}\n' 'php7.4*' 'libapache2-mod-php7.4' 2>/dev/null)   # nếu đã ghim
ls /opt/php2shell-bionic-backup/                     # chọn thư mục sao lưu
sudo rm -f /etc/apt/sources.list.d/relipa-php2shell.list
sudo dpkg -i /opt/php2shell-bionic-backup/<ngày-giờ>/*.deb
sudo apache2ctl configtest && sudo systemctl restart apache2
sudo systemctl restart php7.4-fpm                    # nếu có
sudo supervisorctl restart all
dpkg-query -W php7.4-common                          # về lại 7.4.27 hoặc 7.4.29
```

Rollback đưa server về lại bản **chưa vá**. Báo người phụ trách ngay khi phải rollback.

## Hai thay đổi hành vi (có chủ đích, giống bản vá của PHP)

- Khi một request vượt `memory_limit`, hoặc cấp phát bộ nhớ bị tràn kích thước, process **dừng hẳn** thay vì cố phục hồi. Apache tự tạo process mới cho request sau. Code nào bắt lỗi `Allowed memory size exhausted` để xử lý tiếp sẽ thấy khác.
- Tính năng `session.upload_progress` bị tắt trong code, dù `php -i` vẫn hiện `On`.

## Xử lý sự cố

| Hiện tượng | Nguyên nhân và cách xử lý |
| --- | --- |
| `Chỉ dành cho Ubuntu 18.04 (bionic).` | Server không phải 18.04. Không cài. |
| `Máy này chưa cài php7.4-common.` | Server không dùng php7.4. Không cài. |
| `Không thấy .../Packages.gz` | Sai đường dẫn ở bước 4, hoặc copy thiếu file. Kiểm tra `ls /tmp/php2shell/out`. |
| `sha256sum` báo `FAILED` | File hỏng khi tải hoặc copy. Clone lại repo. |
| `Sao lưu thiếu gói, dừng.` | `dpkg-repack` không sao lưu đủ gói. Chưa có gì thay đổi. Gửi output cho người phụ trách. |
| `apt-get` báo `unmet dependencies` | Server thiếu thư viện và không tải được từ repo Ubuntu. Kiểm tra `sudo apt-get update`. Gửi toàn bộ output, không dùng `--fix-broken` khi chưa hỏi. |
| `apache2ctl configtest` báo lỗi | Xem `/var/log/apache2/error.log`. Nếu cần, rollback. |

## Thông tin bản vá

| | |
| --- | --- |
| Code vá | Commit [`712e60f9ed`](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2) "Avoid state corruption via bailout" của PHP security team, trên branch [`PHP-7.4-CVE-2026-109618-109619`](https://github.com/php/php-src/tree/PHP-7.4-CVE-2026-109618-109619). 17 file, 78 hunk |
| Patch dùng khi build | `php-7.4.33-php2shell.patch` = commit trên, bỏ 4 hunk (`main/main.c` hunk 1, `main/rfc1867.c` hunk 5–7) đã có sẵn nguyên văn trong patch ondrej `0062-Introduce-max_multipart_body_parts-INI.patch`. Áp với `--fuzz=0` |
| Kiểm chứng | Trên cây source cuối cùng, gỡ ngược nguyên bản commit `712e60f9ed` (dry-run, fuzz 0) thành công cả 78/78 hunk, tức là mọi thay đổi của commit đều có mặt |
| Phần còn lại của branch | Ngoài commit vá, branch chỉ khác tarball 7.4.33 ở commit `004cb82750` "Bumb versions" (sửa `NEWS` và `AC_INIT` trong `configure.ac` thành `7.4.34-dev`). Commit này không phải code nên không đưa vào |
| Tarball PHP | `php7.4_7.4.33.orig.tar.xz` từ PPA ondrej, sha256 khớp với `php-7.4.33.tar.xz` của php.net |
| Packaging | `debian/` của source package ondrej `php7.4 1:7.4.33-31+ubuntu22.04.1+deb.sury.org+1`. Chữ ký `.dsc` kiểm bằng key "Ondřej Surý (Automated PPA Upload Key)" `6A1AAD7AE5B401C6E259A7B257067BAA1314C7FC`, key đăng ký trên tài khoản Launchpad `~ondrej` |
| Patch ondrej giữ lại | `0001`–`0135`: patch packaging Debian và các bản vá bảo mật ondrej backport tới đầu tháng 05/2026. Danh sách đầy đủ trong `out/patches-series.txt` |
| Patch ondrej bỏ đi | `0136`–`0164` (29 patch). `0136` (GHSA-m8rr-4c36-8gq4) sửa các dòng `isspace()` ngay cạnh chỗ commit vá sửa trong `main/rfc1867.c`, nên từ `0136` trở đi commit chính chủ không áp nguyên văn được. Các patch bị bỏ gồm nhiều bản vá bảo mật ondrej phát hành từ 05/2026 đến 10/2026 (openssl, pgsql, phar, soap, mysqlnd, FastCGI...) và `0164` (bản ondrej tự chuyển thể từ chính commit vá) |
| Build | Container `ubuntu:18.04`, thư viện build lấy từ repo Ubuntu 18.04 (index bionic của PPA ondrej đã trống) |
| Version | `1:7.4.33-31~ubuntu18.04.1+relipa.php2shell.1`: cao hơn `7.4.27`/`7.4.29` của ondrej, thấp hơn `1:7.4.33-31` đầy đủ của ondrej |
| Kiến trúc | `amd64` |
| Chữ ký | Gói không ký. Nguồn apt dùng `[trusted=yes]`, toàn vẹn kiểm bằng `SHA256SUMS` |

### Kết quả kiểm chứng (22/10/2026, container `ubuntu:18.04`)

PPA ondrej không còn bản `7.4.29`, nên bản giả lập dùng chính các gói đã build, đóng gói lại với version `7.4.29-1+ubuntu18.04.1+deb.sury.org+1`, và `php-common 2:101` của ondrej. Cách này kiểm được đường nâng cấp của `apt` (dependency, conffile, maintainer script, module Apache), không kiểm được khác biệt code giữa 7.4.29 và 7.4.33.

| Kiểm tra | Kết quả |
| --- | --- |
| `install.sh` trên máy có 17 gói như prod (`apache2` + mod_php, `php7.4-fpm`) | 17 gói lên bản vá, bước tự kiểm tra pass |
| `php7.4 -m` trước và sau | Giống hệt |
| `apache2ctl configtest`, `apache2ctl -M` | `Syntax OK`, có `php7_module` |
| `php-fpm7.4 -t` | `test is successful` |
| Code vá có trong binary | `zend_new_array_singleton` có trong `php7.4`, `libphp7.4.so`, `php-fpm7.4` |
| Conffile | Không có `.dpkg-dist`/`.dpkg-old`, cấu hình giữ nguyên |
| Thư viện cài thêm | `libargon2-0`, `libicu60`, `libonig4` từ repo Ubuntu |
| Sao lưu trong `install.sh` | Đủ 17/17 gói vào `/opt/php2shell-bionic-backup/<ngày-giờ>/` |
| Rollback theo hướng dẫn (cách 2) | `dpkg -i` đưa cả 17 gói về `7.4.29-1+ubuntu18.04.1+deb.sury.org+1`, `apache2ctl configtest` pass |

## Build lại (cho người bảo trì)

```bash
mkdir -p out
docker run --rm -e BUILDID=+relipa.php2shell.1 -v "$PWD":/kit:ro -v "$PWD/out":/out ubuntu:18.04 bash /kit/build-deb.sh
```

Mất khoảng 20–25 phút. Khi phát hành bản mới, tăng `BUILDID` (ví dụ `+relipa.php2shell.2`) để `apt` nhận.

## Lưu ý

- Patch là "minimal mitigation" theo lời PHP. Gói này **không** có các bản vá bảo mật ondrej phát hành từ patch `0136` trở đi.
- Ubuntu 18.04 đã hết hỗ trợ tiêu chuẩn, PHP 7.4 đã hết hỗ trợ từ 11/2022. Về lâu dài nên chuyển sang bản OS và PHP còn được hỗ trợ.

## Giấy phép và ghi công

This product includes PHP software, freely available from <http://www.php.net/software/>.
This product includes the Zend Engine, freely available at http://www.zend.com

- Script và tài liệu của repo (`build-deb.sh`, `install.sh`, `strip_hunks.py`, README, NOTICE): BSD-3-Clause, © 2026 Relipa.
- Mã PHP (2 file patch, `out/*.deb`, `source/`): PHP 7.4.33 phát hành theo PHP License 3.01 và Zend Engine License 2.00. Repo dùng mã này theo PHP License v4 và Zend Engine License v3.0 (tương đương BSD-3-Clause), theo điều 5 của PHP License 3.01 và điều 4 của Zend Engine License 2.00. Xem [php.net/license](https://www.php.net/license/).
- Các thành phần khác trong `.deb` (thư viện đi kèm, có phần LGPL; packaging Debian của Ondřej Surý) giữ giấy phép riêng, liệt kê trong `/usr/share/doc/php7.4-common/copyright` của gói. Không xoá file này khi phát hành lại.
- Mã nguồn tương ứng với các gói `.deb` nằm trong `source/` (checksum trong `source/SHA256SUMS`), dựng lại được bằng `build-deb.sh`.
- Bản build không chính thức, không liên kết với hay được The PHP Group, Zend, Perforce hoặc Ondřej Surý xác nhận.

## Tài liệu

- [Ubuntu – CVE-2026-109618](https://ubuntu.com/security/CVE-2026-109618)
- [Ubuntu – CVE-2026-109619](https://ubuntu.com/security/CVE-2026-109619)
- [php-src commit 712e60f9ed](https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2)
- [php-src branch PHP-7.4-CVE-2026-109618-109619](https://github.com/php/php-src/tree/PHP-7.4-CVE-2026-109618-109619)
- [PPA ondrej/php](https://launchpad.net/~ondrej/+archive/ubuntu/php)
