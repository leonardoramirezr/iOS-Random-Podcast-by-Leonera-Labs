# Random Podcast by Leonera Labs

An iPhone app (SwiftUI, iOS 17+) that connects to Spotify, lets you save podcasts, and picks a random episode from them. The episode opens in the Spotify app with one tap.

- Interface in English and Spanish. The app follows the language of the iPhone.
- No third-party dependencies. Only Apple frameworks (SwiftUI, AuthenticationServices, CryptoKit, Security).

## Features

- **Connect with Spotify** using Authorization Code with PKCE. No client secret ships in the app. Tokens are stored in the Keychain.
- **Search and save podcasts** inside the app. Saved podcasts persist on the device.
- **Random episode**:
  1. Pick a saved podcast at random.
  2. Read the episode count from `GET /shows/{id}/episodes`, split it into pages of 50, and pick a random page.
  3. Fetch that page and pick a random episode inside it. Entries that are `null` (unavailable in the market) are skipped.
- **Open in Spotify**: a universal link (`https://open.spotify.com/episode/{id}`). When the Spotify app is installed, iOS opens the episode there. Otherwise it opens in Safari.

## Spotify setup

1. Create an app at the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard). Select the **Web API**.
2. Add this redirect URI: `randompodcast://spotify-callback`
3. Copy the **Client ID** into `SPOTIFY_CLIENT_ID` in `project.yml`. The Client ID is public, so it is safe to commit.

Limits that apply to Development Mode apps (the mode new apps start in):

- The app owner needs an active Spotify Premium subscription.
- Up to 5 users can be added to the app.
- Show search returns at most 10 results per request.

## Local development

```sh
brew install xcodegen
xcodegen generate
open RandomPodcast.xcodeproj
```

`RandomPodcast.xcodeproj` and `Config/Info.plist` are generated from `project.yml`, so they are not committed.

## Continuous integration

The workflow `.github/workflows/build.yml` runs on every push to any branch except `gh-pages`, and on manual dispatch.

### Secrets

Add these under **Settings › Secrets and variables › Actions**:

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | Key ID of the App Store Connect Team Key (role Admin) |
| `ASC_ISSUER_ID` | Issuer ID of the App Store Connect account |
| `ASC_KEY_P8` | Full contents of the `.p8` file |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

Behavior:

- **All four secrets set:** the app is archived with automatic signing, exported as Ad Hoc, verified, and published.
- **None set:** an unsigned IPA is built and uploaded as a workflow artifact. Nothing is published.
- **Only some set:** the run fails with an error that lists the missing secrets.

### What a signed build does

1. Checks that the API key works and that at least one iOS device is enabled.
2. Archives with `xcodebuild -allowProvisioningUpdates`. Xcode registers the App ID and creates the profiles.
3. Exports with the `release-testing` (Ad Hoc) method. Every device registered in App Store Connect is included.
4. Checks that every bundle in the IPA has an Ad Hoc `embedded.mobileprovision` and prints the device count.
5. Publishes the build to GitHub Pages and creates a GitHub release.
6. Revokes only the temporary "Apple Development" certificate that the archive created. It runs even if an earlier step failed.

### Versions and releases

| Branch | Tag | Release |
| --- | --- | --- |
| `main` | `0.x.0`, where `x` is the last `0.x.0` tag plus one | Stable, marked Latest |
| Any other branch | `build-<run_number>-<sha7>` | Pre-release |

Concurrency: builds on `main` are serialized in one group. Every other build has its own group. No build is cancelled.

The build number (`CFBundleVersion`) is the workflow run number, and `CFBundleShortVersionString` is the version from the tag.

### GitHub Pages

Each build is published to the `gh-pages` branch in its own folder, named after the tag:

- `RandomPodcast.ipa`
- `manifest.plist`, with the 57 px and 512 px icons
- `index.html`, with an install button (`itms-services://`)
- `build.json`, with the build metadata and the commit title

The root `index.html` lists every build and has a button to the latest stable build. `scripts/publish-pages.sh` keeps every `main` build and the 20 most recent branch builds. It rewrites `gh-pages` as a single orphan commit so IPA files do not pile up in history.

**One-time setup, after the first signed build:** open **Settings › Pages**, set the source to the `gh-pages` branch and the `/ (root)` folder.

### Adding an iPhone

1. Register the device UDID in the [Apple Developer portal](https://developer.apple.com/account/resources/devices/list). You can also register it with the App Store Connect API.
2. Push any commit. The next build creates an Ad Hoc profile that includes the new device.
3. Open the Pages site in Safari on the iPhone and tap **Install on iPhone**.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/asc.py` | App Store Connect API: key check, device check, temporary certificate revocation. Uses only the standard library and `openssl`. |
| `scripts/verify_adhoc.py` | Verifies the Ad Hoc profiles inside the IPA and writes a summary. |
| `scripts/make_build_page.py` | Creates the per-build Pages folder (IPA, manifest, icons, install page, `build.json`). |
| `scripts/site.py` | Prunes old builds and regenerates the Pages index. |
| `scripts/publish-pages.sh` | Publishes a build folder to `gh-pages` as a single orphan commit, with retries. |
