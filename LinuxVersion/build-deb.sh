#!/usr/bin/env bash
# build-deb.sh - build the Debian package of SD Core Transfer Utility.
#
#   LinuxVersion/build-deb.sh            # build the program, then the package
#   LinuxVersion/build-deb.sh --no-build # package the binaries already in bin/
#
# Output: build/deb/transfer-utility.deb (no version in the file name, like
# the Windows transfer-utility-setup.exe).  The package's own version, which
# apt and dpkg use, is AppVersion in src/uModels.pas plus the revision below.
#
# One package for Debian 13 and Ubuntu 24.04 and later: the binaries need
# nothing newer than GLIBC_2.34 (checked below), and the dependencies are
# named so that both the t64 package names (Debian 13, Ubuntu 24.04+) and the
# older ones satisfy them.  No source code goes into the package; About shows
# the GitHub address.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The package revision is the number of commits on this branch, so each new
# build is an upgrade for apt (1.1.0-23, 1.1.0-24, ...) while AppVersion, the
# program's own version, stays as the owner sets it.
REVISION="$(git -C "$ROOT" rev-list --count HEAD)"
MAX_GLIBC=2.34   # Ubuntu 24.04 has 2.39, Debian 13 has 2.41

cd "$ROOT"
if [ "${1:-}" != "--no-build" ]; then
  LinuxVersion/build.sh
fi

VERSION="$(sed -n "s/^ *AppVersion *= *'\([^']*\)'.*/\1/p" src/uModels.pas)"
[ -n "$VERSION" ] || { echo "AppVersion not found in src/uModels.pas"; exit 1; }
DEBVER="$VERSION-$REVISION"
PKG=transfer-utility
OUT="$ROOT/build/deb"
STAGE="$OUT/${PKG}_${DEBVER}_amd64"

for f in bin/sd-transfer bin/sd-askpass; do
  [ -x "$f" ] || { echo "missing $f; run LinuxVersion/build.sh"; exit 1; }
done

# Refuse a binary that needs a newer glibc than the oldest supported system.
need="$( { objdump -T bin/sd-transfer 2>/dev/null; objdump -T bin/sd-askpass 2>/dev/null; } |
  grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -1)" || true
if [ -n "$need" ] && [ "$(printf '%s\n%s\n' "$need" "$MAX_GLIBC" | sort -V | tail -1)" != "$MAX_GLIBC" ]; then
  echo "REFUSED: the binaries need GLIBC_$need; the oldest supported system has $MAX_GLIBC."
  exit 1
fi

rm -rf "$STAGE"
install -d "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/usr/lib/sd-transfer" \
  "$STAGE/usr/share/applications" "$STAGE/usr/share/icons/hicolor/scalable/apps" \
  "$STAGE/usr/share/doc/$PKG"

# The two programs must sit together: sd-transfer finds sd-askpass beside itself.
install -m 755 bin/sd-transfer bin/sd-askpass "$STAGE/usr/lib/sd-transfer/"
# A wrapper rather than a symlink, so the program's own path is the real one.
cat > "$STAGE/usr/bin/sd-transfer" <<'EOF'
#!/bin/sh
exec /usr/lib/sd-transfer/sd-transfer "$@"
EOF
chmod 755 "$STAGE/usr/bin/sd-transfer"

install -m 644 LinuxVersion/sd-transfer.svg \
  "$STAGE/usr/share/icons/hicolor/scalable/apps/sd-transfer.svg"
cat > "$STAGE/usr/share/applications/sd-transfer.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=SD Core Transfer Utility
GenericName=File Transfer
Comment=Move text files between this computer and an SD Core server
Exec=sd-transfer
Icon=sd-transfer
Terminal=false
Categories=Development;Network;FileTransfer;
StartupWMClass=sd-transfer
EOF
chmod 644 "$STAGE/usr/share/applications/sd-transfer.desktop"

DOC="$STAGE/usr/share/doc/$PKG"
{
  echo "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/"
  echo "Upstream-Name: SD Core Transfer Utility"
  echo "Source: https://github.com/dmontaine/TransferUtility"
  echo
  echo "Files: *"
  echo "License: BSD-2-Clause"
  sed 's/^$/./; s/^/ /' LICENSE
} > "$DOC/copyright"
install -m 644 docs/USER_GUIDE.md docs/INSTALL.md "$DOC/"
printf '%s (%s) stable; urgency=medium\n\n  * Release %s.\n\n -- Donald Montaine <dmontaine@users.noreply.github.com>  %s\n' \
  "$PKG" "$DEBVER" "$VERSION" "$(date -R)" | gzip -9n > "$DOC/changelog.Debian.gz"
chmod 644 "$DOC"/*

SIZE="$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $DEBVER
Section: net
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libc6 (>= $MAX_GLIBC), libgtk-3-0t64 | libgtk-3-0, libharfbuzz-gobject0, libglib2.0-bin, openssh-client, bsdutils
Recommends: xdg-utils
Maintainer: Donald Montaine <dmontaine@users.noreply.github.com>
Homepage: https://github.com/dmontaine/TransferUtility
Description: SD Core Transfer Utility
 A desktop client that moves plain-text files between this computer and
 your own account on an SD Core server (SD Core or SD Core Solo, on Linux or
 Windows) over ssh and sftp, using only standard SD Core commands. Files are
 moved by drag and drop between a local pane and the account's xfer.in,
 xfer.out or bp.
EOF

# Refresh the menu and icon caches where the tools exist; removing the
# package leaves ~/.config/sd-transfer-utility and ~/.ssh alone.
for script in postinst postrm; do
  cat > "$STAGE/DEBIAN/$script" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
fi
exit 0
EOF
  chmod 755 "$STAGE/DEBIAN/$script"
done

find "$STAGE" -type d -exec chmod 755 {} +
DEB="$OUT/$PKG.deb"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$DEB" >/dev/null
rm -rf "$STAGE"
echo "Built $DEB"
dpkg-deb --info "$DEB" | sed -n 's/^ *\(Package\|Version\|Depends\|Installed-Size\):/  &/p'
