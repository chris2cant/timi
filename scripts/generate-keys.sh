#!/usr/bin/env bash
# Run ONCE per developer machine. Creates the Sparkle EdDSA key pair with the official tool.
# The PRIVATE key is stored in your macOS login Keychain. NEVER COMMIT THE PRIVATE KEY.
# Only the PUBLIC key goes in Timi/Info.plist (SUPublicEDKey).
set -euo pipefail
cd "$(dirname "$0")/.."

tools="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [[ ! -x "$tools/generate_keys" ]]; then
  echo "Resolving the Sparkle package to get its official tools..."
  xcodebuild -resolvePackageDependencies -project Timi.xcodeproj -scheme Timi -derivedDataPath build >/dev/null
fi

# Without options, generate_keys creates the key if missing, otherwise prints the existing public key.
"$tools/generate_keys"

echo
echo "Copy the public key above into SUPublicEDKey in Timi/Info.plist."
echo "Back up the private key OUTSIDE the repository (password manager / encrypted volume):"
echo "  $tools/generate_keys -x /secure/location/sparkle_private_key"
echo "NEVER COMMIT THE PRIVATE KEY. If it is lost, existing installs cannot be updated automatically."
