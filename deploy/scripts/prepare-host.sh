#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo >&2 "Run this one-time storage setup script with sudo"
    exit 1
fi

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
data_root=${1:-/data/swm}

case "$data_root" in
    /*) ;;
    *)
        echo >&2 "The storage root must be an absolute path"
        exit 1
        ;;
esac

if [ "$data_root" = "/" ]; then
    echo >&2 "Refusing to use the filesystem root as the SWM data directory"
    exit 1
fi

ensure_directory() {
    path=$1
    if [ ! -d "$path" ]; then
        install -d -o 33 -g 33 -m 2775 "$path"
    fi
}

ensure_directory "$data_root"

ensure_directory "$data_root/public"
ensure_directory "$data_root/private"

# Application code may create upload/document directories dynamically.
# Apply PHP-FPM permissions to the complete persistent trees.
chown -R 33:33 "$data_root/public" "$data_root/private"
find "$data_root/public" "$data_root/private" -type d -exec chmod 2775 {} +
find "$data_root/public" "$data_root/private" -type f -exec chmod 0664 {} +

if [ -d "$repository_root/SWM/Backend/public/UlbLog" ]; then
    cp -a -n "$repository_root/SWM/Backend/public/UlbLog/." "$data_root/public/UlbLog/"
    chown -R 33:33 "$data_root/public/UlbLog"
fi

echo "Prepared persistent public/private directories at $data_root"

