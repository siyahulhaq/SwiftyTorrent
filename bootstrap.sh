#!/bin/bash

set -e
set -o pipefail

LIBTORRENT_VER=2.1.1
BOOST_VER=1.84.0

ROOT_DIR=$(pwd)
DEPS_DIR="$ROOT_DIR/Thirdparties"

rm -rf "$DEPS_DIR/"

## libtorrent

LIBTORRENT_DIR="$DEPS_DIR/libtorrent-$LIBTORRENT_VER"
LIBTORRENT_XCFRAMEWORK_ZIP="$LIBTORRENT_DIR/libtorrent.xcframework.zip"

echo "[*] downloading libtorrent..."
curl -L -o "$LIBTORRENT_XCFRAMEWORK_ZIP" --create-dirs \
  "https://github.com/siyahulhaq/libtorrent-Apple/releases/download/$LIBTORRENT_VER/libtorrent.xcframework.zip"

echo "[*] extracting libtorrent..."
cd "$LIBTORRENT_DIR"
unzip -q -o "libtorrent.xcframework.zip"
rm -f "libtorrent.xcframework.zip"

## boost

BOOST_DIR="$DEPS_DIR/boost-$BOOST_VER"
BOOST_TARBALL="$BOOST_DIR/boost-$BOOST_VER.tar.gz"

echo "[*] downloading boost..."
BOOST_VER_FIX=$(echo $BOOST_VER | sed -E "s/\./_/g")
curl -L -o "$BOOST_TARBALL" --create-dirs \
  "https://archives.boost.io/release/$BOOST_VER/source/boost_$BOOST_VER_FIX.tar.gz"

echo "[*] extracting boost..."
mkdir -p "$BOOST_DIR"
tar -xzf "$BOOST_TARBALL" --strip 1 -C "$BOOST_DIR"

rm "$BOOST_TARBALL"

echo "[+] done."
