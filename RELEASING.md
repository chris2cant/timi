# Releasing Timi

Timi updates itself with [Sparkle 2](https://sparkle-project.org). The feed (`appcast.xml`) lives in this
repository (served by `raw.githubusercontent.com`, so the repository must be **public**), and archives are
GitHub Releases of this same repository. Everything is HTTPS.

> **NEVER COMMIT THE PRIVATE KEY.** The Sparkle private key stays in your macOS Keychain. Anyone holding
> it can ship an update to every install. If it is lost, existing installs can no longer be updated
> automatically (there is no Apple signature to fall back on).

## First time only

1. Open the project once in Xcode (or run `xcodebuild -resolvePackageDependencies -project Timi.xcodeproj -scheme Timi`) so Sparkle's tools are downloaded.
2. Run `./scripts/generate-keys.sh` (once per machine). It prints the **public** key.
3. Paste it into `SUPublicEDKey` in `Timi/Info.plist` and commit.
4. Back up the private key outside the repo (`generate_keys -x <file>` into a password manager or encrypted volume). Never put it in the repo.
5. Create a stable self-signed code-signing certificate (free, no Apple Developer account): Keychain Access → Certificate Assistant → Create a Certificate → name `Timi Local Signing`, type *Code Signing*. It keeps your macOS permissions (Accessibility, microphone) across updates. Do not export it into the repo.
6. Check `scripts/release.conf` (`OWNER`, `DISTRIBUTION_REPO`, `SIGN_IDENTITY`).
7. Before the first public release, choose a real bundle identifier (currently the placeholder `com.example.Timi`); changing it later breaks update continuity and permissions.
8. On GitHub: enable 2FA, protect `main` and `v*` tags, add a CODEOWNERS entry for `appcast.xml`.

## Each release

1. Make and commit your changes (the working tree must be clean).
2. `./scripts/release.sh 1.1.0` — bumps `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (always strictly increasing), builds Release, zips only the `.app` with `ditto`, writes notes, then signs archive and feed with `generate_appcast`. It publishes nothing.
3. Test `dist/v1.1.0/Timi-1.1.0.zip` (install it, update from the previous version).
4. Publish (commands are printed by the script): commit `appcast.xml`, tag `v1.1.0`, `gh release create` with the zip, then push. Create the Release **before** pushing the appcast so the download exists when clients see it.

Installed Macs then detect the new version automatically (daily check) and always ask before installing.

## Limits and security notes

- Timi is neither Developer ID signed nor notarized. **Sparkle does not remove Gatekeeper warnings** for the first installation (right-click → Open, or `xattr -dr com.apple.quarantine Timi.app`). Updates downloaded by Sparkle are verified by the EdDSA signature, not by Apple.
- Because there is no notarization, publish the SHA-256 printed by `release.sh` with each Release and the `SUPublicEDKey` fingerprint in the README so people can verify what they install.
- `com.apple.security.cs.disable-library-validation` is enabled so a self-signed app can load `Sparkle.framework`. Drop it when adopting Developer ID.
- Developer ID + notarization can be added later without changing the Sparkle architecture (same EdDSA key, same appcast).
- No secrets in CI: do not give workflows triggered by pull requests access to the Sparkle key.
