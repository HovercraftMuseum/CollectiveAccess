#!/bin/sh
# Smoke test for a freshly built image. Used by CI before anything is
# published, and handy locally:
#
#   scripts/smoke-test.sh ghcr.io/your-org/collective-access:test
#
# Checks, without needing a database:
#   - required and recommended PHP extensions are loaded
#   - Composer's platform check passes (catches PHP-version mismatches with
#     the bundled vendor/ directory)
#   - media tools CA relies on are present and run
#   - Apache configuration is valid
#   - setup.php parses
set -eu

IMAGE="${1:?usage: smoke-test.sh <image>}"
fail=0

run() {
    docker run --rm --entrypoint "" "$IMAGE" "$@"
}

check() {
    label="$1"; shift
    if out=$(run "$@" 2>&1); then
        echo "  ok    $label"
    else
        echo "  FAIL  $label"
        echo "$out" | sed 's/^/        /'
        fail=1
    fi
}

echo "Smoke testing $IMAGE"

echo "PHP extensions:"
for ext in bcmath curl exif gd gmp imagick intl mbstring mysqli pcntl posix redis xml zip; do
    check "php ext $ext" php -r "exit(extension_loaded('$ext') ? 0 : 1);"
done
# OPcache registers itself as "Zend OPcache", not "opcache"
check "php ext opcache" php -r "exit(extension_loaded('Zend OPcache') ? 0 : 1);"
check "gmagick NOT loaded (CA: never install both)" php -r "exit(extension_loaded('gmagick') ? 1 : 0);"

echo "Application:"
check "composer platform check" php /var/www/html/vendor/composer/platform_check.php
check "vendor autoloader loads" php -r "require '/var/www/html/vendor/autoload.php';"
check "setup.php syntax" php -l /var/www/html/setup.php
check "caUtils present" test -f /var/www/html/support/bin/caUtils
check "ca-prune-logs present" test -x /usr/local/bin/ca-prune-logs
check "version file" grep -q "__CollectiveAccess_Version__" /var/www/html/app/version.php

echo "Media tools:"
check "ffmpeg"      ffmpeg -hide_banner -version
check "ghostscript" gs --version
check "graphicsmagick" gm version
check "imagemagick" sh -c 'convert -version || magick -version'
check "pdftotext"   test -x /usr/bin/pdftotext
check "mediainfo"   mediainfo --version
check "exiftool"    exiftool -ver

echo "Web server:"
check "apache config" apache2ctl -t

if [ "$fail" -ne 0 ]; then
    echo "Smoke test FAILED"
    exit 1
fi
echo "Smoke test passed"
