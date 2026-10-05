#!/usr/bin/env bash
# Usage: ./scripts/release.sh 1.2.0
# Builds, signs, zips and prepares the appcast for a release. Pushes/tags/publishes NOTHING:
# the commands to run afterwards are printed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=release.conf
source scripts/release.conf

die() { echo "error: $*" >&2; exit 1; }

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.0"

pbxproj="Timi.xcodeproj/project.pbxproj"
tools="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ "$OWNER" =~ ^[A-Za-z0-9._-]+$ && "$DISTRIBUTION_REPO" =~ ^[A-Za-z0-9._-]+$ ]] \
  || die "invalid OWNER/DISTRIBUTION_REPO in scripts/release.conf"
[[ "$OWNER" != "<OWNER>" && "$DISTRIBUTION_REPO" != "<DISTRIBUTION_REPO>" ]] || die "configure scripts/release.conf"

# 1. Clean working tree (untracked files ignored by .gitignore don't count).
[[ -z "$(git status --porcelain)" ]] || die "working tree is not clean"

# Safety: the update signing key must never come from a file inside the repo.
[[ -z "${SPARKLE_ED_KEY_FILE:-}" ]] || die "SPARKLE_ED_KEY_FILE is set: the key must stay in the Keychain"

# The public key must have been configured.
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Timi/Info.plist)"
[[ "$public_key" != REPLACE_* && -n "$public_key" ]] || die "SUPublicEDKey not set: run scripts/generate-keys.sh"

# 2. Version and build number must strictly increase.
current_version="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$pbxproj" | head -1)"
current_build="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);/\1/p' "$pbxproj" | head -1)"
[[ "$current_build" =~ ^[0-9]+$ ]] || die "cannot read CURRENT_PROJECT_VERSION"
if [[ -f appcast.xml ]]; then
  published_build="$(sed -n 's|.*<sparkle:version>\([0-9]*\)</sparkle:version>.*|\1|p' appcast.xml | sort -n | tail -1)"
  if [[ -n "$published_build" && "$published_build" -gt "$current_build" ]]; then current_build="$published_build"; fi
fi
[[ "$(printf '%s\n%s\n' "$current_version" "$version" | sort -V | tail -1)" == "$version" \
   && "$current_version" != "$version" ]] || die "version $version must be greater than $current_version"
build=$((current_build + 1))
git rev-parse "v$version" >/dev/null 2>&1 && die "tag v$version already exists"

echo "Releasing $APP_NAME $version (build $build)"

# 3. Bump versions (both configurations).
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $build;/" "$pbxproj"

# 4. Release build, signed with the stable identity.
[[ -x "$tools/generate_appcast" ]] || xcodebuild -resolvePackageDependencies -project Timi.xcodeproj -scheme Timi -derivedDataPath build >/dev/null
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "warning: ad-hoc signing, macOS permissions will be asked again after each update" >&2
elif ! security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
  git checkout -- "$pbxproj"
  die "signing identity '$SIGN_IDENTITY' not found (see RELEASING.md)"
fi
xcodebuild build -project Timi.xcodeproj -scheme Timi -configuration Release -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" -quiet
app="build/Build/Products/Release/$APP_NAME.app"
codesign --verify --deep --strict "$app"

# 5. Archive: only the .app, keeping symlinks, permissions and resource forks.
out="dist/v$version"
rm -rf "$out"; mkdir -p "$out"
zip_name="$APP_NAME-$version.zip"
ditto -c -k --keepParent "$app" "$out/$zip_name"

# 6. Release notes (Markdown, supported since Sparkle 2.9): commits since the previous tag.
previous_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
{
  echo "## $APP_NAME $version"
  echo
  git log --no-merges --format='- %s' ${previous_tag:+"$previous_tag..HEAD"}
} > "$out/$APP_NAME-$version.md"

# 7. Appcast: generate_appcast signs the archive (EdDSA, key from Keychain) and the feed.
# Keep the existing entries by seeding the folder with the current appcast.
[[ -f appcast.xml ]] && cp appcast.xml "$out/appcast.xml"
"$tools/generate_appcast" \
  --download-url-prefix "https://github.com/$OWNER/$DISTRIBUTION_REPO/releases/download/v$version/" \
  "$out"
cp "$out/appcast.xml" appcast.xml

shasum -a 256 "$out/$zip_name" | tee "$out/$zip_name.sha256"

cat <<MSG

Prepared. Nothing was pushed. Test dist/v$version/$zip_name, then:

  git add "$pbxproj" appcast.xml
  git commit -m "Release $version"
  git tag v$version
  gh release create v$version "$out/$zip_name" --repo $OWNER/$DISTRIBUTION_REPO \\
    --title "$APP_NAME $version" --notes-file "$out/$APP_NAME-$version.md"
  git push origin main v$version      # publishes appcast.xml: do it AFTER the release exists
MSG
