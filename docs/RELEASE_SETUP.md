# Release Setup Guide

This guide explains how to set up automated releases for Delicious Island with code signing, notarization, and Sparkle auto-updates.

## Prerequisites

1. **Apple Developer Account** with Developer ID certificates
2. **GitHub repository** with Actions enabled
3. **Sparkle EdDSA keys** (already generated in `.sparkle-keys/`)

## GitHub Secrets

Add these secrets to your repository (Settings → Secrets → Actions):

| Secret | Description | How to Get |
|--------|-------------|------------|
| `APPLE_CERTIFICATE_P12` | Base64-encoded Developer ID certificate | See below |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the P12 file | Set during export |
| `APPLE_ID` | Your Apple ID email | Your developer account email |
| `APPLE_APP_PASSWORD` | App-specific password | [appleid.apple.com](https://appleid.apple.com) |
| `APPLE_TEAM_ID` | Developer Team ID | Developer portal |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for Sparkle | `.sparkle-keys/eddsa_private_key` |

### Getting APPLE_CERTIFICATE_P12

1. Open **Keychain Access** on your Mac
2. Find your "Developer ID Application" certificate
3. Right-click → Export → Save as `.p12` file
4. Set a strong password (save this as `APPLE_CERTIFICATE_PASSWORD`)
5. Base64 encode the file:
   ```bash
   base64 -i certificate.p12 | pbcopy
   ```
6. Paste the result as `APPLE_CERTIFICATE_P12` secret

### Getting APPLE_APP_PASSWORD

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in → Security → App-Specific Passwords
3. Generate a new password for "Delicious Island CI"
4. Save as `APPLE_APP_PASSWORD` secret

### Getting APPLE_TEAM_ID

1. Go to [developer.apple.com](https://developer.apple.com)
2. Account → Membership → Team ID
3. Copy the 10-character Team ID

### Getting SPARKLE_PRIVATE_KEY

The EdDSA private key is already generated at `.sparkle-keys/eddsa_private_key`:
```bash
cat .sparkle-keys/eddsa_private_key | pbcopy
```
Paste as `SPARKLE_PRIVATE_KEY` secret.

## Enable GitHub Pages

1. Go to repository Settings → Pages
2. Source: Deploy from a branch
3. Branch: `main`, folder: `/docs`
4. Save

The appcast will be available at:
`https://grokr-labs.github.io/delicious-island/appcast.xml`

## Release Workflow

### Automatic Releases (Recommended)

1. Make changes using conventional commits:
   - `feat: add new feature` → minor version bump
   - `fix: bug fix` → patch version bump
   - `feat!: breaking change` → major version bump

2. Push to `main`:
   ```bash
   git push origin main
   ```

3. `semantic-release` creates a version tag (e.g., `v0.2.0`)

4. `build-release.yml` workflow:
   - Builds and signs the app
   - Notarizes with Apple
   - Creates signed DMG
   - Generates Sparkle signature
   - Creates delta updates (if previous versions exist)
   - Uploads to GitHub Release
   - Updates appcast.xml

### Manual Release (Alternative)

```bash
# Build the app
./scripts/build.sh

# Create release (notarize, DMG, sign, upload)
./scripts/create-release.sh
```

## Testing Updates

1. Install an older version of Delicious Island
2. Check for updates in the app
3. Verify the update downloads and installs correctly

## Troubleshooting

### Notarization Fails
- Ensure `APPLE_ID` and `APPLE_APP_PASSWORD` are correct
- Check that the certificate is "Developer ID Application" (not Mac Developer)
- Verify Team ID matches the certificate

### Sparkle Signature Invalid
- Ensure `SPARKLE_PRIVATE_KEY` matches `SUPublicEDKey` in Info.plist
- Regenerate keys if needed: `./scripts/generate-keys.sh`

### DMG Not Appearing in Release
- Check Actions logs for upload errors
- Verify `GITHUB_TOKEN` has write permissions

## File Locations

| File | Purpose |
|------|---------|
| `.github/workflows/release.yml` | Semantic-release versioning |
| `.github/workflows/build-release.yml` | macOS build and signing |
| `docs/appcast.xml` | Sparkle update feed |
| `docs/notes/*.html` | Per-version release notes |
| `scripts/create-release.sh` | Manual release script |
| `.sparkle-keys/` | EdDSA signing keys (gitignored) |
