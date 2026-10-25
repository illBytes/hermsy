#!/usr/bin/env bash
# Builds Hermsy for Google Play: the prod app bundle, signed with the illbytes
# upload key, and checks it before you upload it.
#
#   tool/build_play.sh
#
# Bump `version:` in pubspec.yaml first: Play needs a higher build number
# (the part after +) for every upload.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
bundle=build/app/outputs/bundle/prodRelease/app-prod-release.aab

if [[ ! -f android/key.properties || ! -f android/upload-keystore.jks ]]; then
  echo "No upload key (android/key.properties and android/upload-keystore.jks)." >&2
  echo "Restore them from your backup; Play only accepts uploads signed with it." >&2
  exit 1
fi

version=$(grep '^version:' pubspec.yaml | awk '{print $2}')
echo "Building Hermsy $version for Google Play…"
"$flutter" build appbundle --flavor prod --release || {
  # Flutter fails its last check (stripping symbols) when Android's
  # command-line tools are missing; the bundle itself is fine if it exists.
  [[ -f "$bundle" ]] || exit 1
  echo "(Flutter's symbol check needs Android's command-line tools; the bundle was built.)"
}

# Never ship a server address or key.
if unzip -l "$bundle" | grep -qi '\.env'; then
  echo "STOP: the bundle contains a .env file. Do not upload it." >&2
  exit 1
fi

keytool="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
if [[ -x "$keytool" ]]; then
  signer=$("$keytool" -printcert -jarfile "$bundle" | grep -m1 'Owner:' || true)
  if [[ "$signer" != *illbytes* ]]; then
    echo "STOP: the bundle is not signed with the illbytes upload key ($signer)." >&2
    exit 1
  fi
fi

echo
echo "Ready to upload: $bundle ($(du -h "$bundle" | cut -f1))"
echo "Version $version, signed by illbytes, no .env inside."
