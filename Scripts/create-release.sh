#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: $0 <version>"
  exit 64
fi

project_root=${0:A:h:h}
version="$1"
archive_path="$project_root/dist/LimitChecker-$version-macos-universal.zip"
dmg_path="$project_root/dist/LimitChecker-$version-macos-universal.dmg"

LIMITCHECKER_VERSION="$version" "$project_root/Scripts/build-app.sh"
rm -f "$archive_path" "$archive_path.sha256"
ditto --norsrc -c -k --keepParent "$project_root/dist/LimitChecker.app" "$archive_path"
"$project_root/Scripts/create-dmg.sh" "$version" >/dev/null

# The in-app updater refuses to install a download without a matching digest,
# so every published asset needs its checksum beside it. Record the bare file
# name, not the build path, so `shasum -c` works wherever the file is checked.
for asset in "$archive_path" "$dmg_path"; do
  (cd "${asset:h}" && shasum -a 256 "${asset:t}" > "${asset:t}.sha256")
done

print "$archive_path"
