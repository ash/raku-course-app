# App Store submission kit — Learn Raku

Everything needed to create the App Store Connect listing for **Learn Raku**
(the Course of Raku by Andrew Shitov, offline). Generated from the app itself,
so the numbers match the bundled content.

## App identity

| Field | Value |
|-------|-------|
| App name | **Learn Raku** |
| Bundle ID | **online.deepsoft.learnraku** |
| Version / build | 1.0.0 (3) — see `pubspec.yaml` `version:`. Build 1 was rejected (blank screen at launch); build 3 is the resubmission |
| Platforms | iPhone + iPad (universal; `TARGETED_DEVICE_FAMILY = 1,2`) |
| Primary category | Education |
| Secondary category | Developer Tools |
| Age rating | 4+ (no objectionable content) |
| Price | Free |

## Listing text

The listing copy lives in `metadata/` in the [fastlane `deliver`](https://docs.fastlane.tools/actions/deliver/)
layout, so it can be pushed with `fastlane deliver` or copy-pasted by hand:

```
metadata/
  en-US/
    name.txt              Learn Raku
    subtitle.txt          The Course of Raku, offline
    promotional_text.txt  (≤170)
    description.txt        (≤4000)
    keywords.txt          (≤100, comma-separated)
    release_notes.txt     "What's New" for 1.0
    support_url.txt        https://deepsoft.online/support/learn-raku
    marketing_url.txt      https://deepsoft.online/mobile/learn-raku
    privacy_url.txt        https://deepsoft.online/policy/learn-raku
  primary_category.txt / secondary_category.txt / copyright.txt
  review_information/     App Review contact + notes
```

The support and privacy pages these URLs point to were created on
deepsoft.online as part of this task (`/policy/learn-raku`, `/support/learn-raku`)
and the app is listed on `/mobile`.

## Screenshots

Captured from the app at the two required App Store display sizes via the
integration-test harness (`integration_test/screenshot_test.dart` +
`test_driver/screenshot_driver.dart`). PNGs are in `screenshots/`:

| Folder | Captured on | Pixel size | App Store Connect slot |
|--------|-------------|-----------|------------------------|
| `screenshots/iphone-6.3/` | iPhone 17 Pro | 1206 × 2622 | **iPhone 6.1" or 6.3"** — "Dynamic Island (medium display)", the one iPhone size Apple **requires** |
| `screenshots/iphone-6.9/` | iPhone 17 Pro Max | 1320 × 2868 | iPhone 6.9" — Dynamic Island (large display), optional |
| `screenshots/iphone-6.5/` | from the 6.9" set | 1284 × 2778 | iPhone 6.5" — Face ID (large display), optional |
| `screenshots/ipad-13/`    | iPad Pro 13-inch  | 2064 × 2752 | **iPad 13"**, required for an iPad app |

Apple's rules as of October 2026
([screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)):
at least one screenshot for "iPhone with Dynamic Island (medium display)"
(1206 × 2622 or 1179 × 2556) and, for an iPad app, one for the 13" iPad; other
sizes are scaled from those when missing. App Store Connect checks the exact
pixel size per slot and answers "File dimensions are invalid" for a set dropped
into the wrong one — so every file name carries its size
(`01-lesson-run-1206x2622.png`). iPhone Duo screenshots are optional until
April 2027, when Apple requires them for apps built with the iOS 27.1 SDK; the
Xcode 26.5 simulators have no iPhone Duo to capture on.

Every file is flattened (no alpha channel), sRGB, 72 dpi: Apple does not accept
transparency, and Google Play accepts only 24-bit PNG.

Ten shots per set, in store order — what is new first, since most visitors see
only the first two or three: `01-lesson-run` (a lesson after tapping Run),
`02-input` (a program waiting for the reader's answer), `03-playground`,
`04-home`, `05-final-test`, `06-quiz`, `07-exercise`, `08-home-dark`,
`09-search`, `10-part`. The run shots execute real Raku through the bundled
engine.

To regenerate (a simulator of each device must be booted), capture, then
flatten, then add the size to the names:

```bash
for d in "iPhone 17 Pro:iphone-6.3" "iPhone 17 Pro Max:iphone-6.9" "iPad Pro 13-inch (M5):ipad-13"; do
  flutter drive --driver=test_driver/screenshot_driver.dart \
    --target=integration_test/screenshot_test.dart \
    -d "${d%%:*}" --dart-define=SS_DEVICE="${d##*:}"
done
cd appstore/screenshots
# the 6.5" set is the 6.9" one scaled by 1284/1320, 6 px off the top and bottom
mkdir -p iphone-6.5
for f in iphone-6.9/*.png; do
  magick "$f" -resize 1284x -gravity center -crop 1284x2778+0+0 +repage "iphone-6.5/${f#*/}"
done
for f in */*.png; do
  magick "$f" -background white -alpha remove -alpha off -density 72 PNG24:"$f"
  case "$f" in *-[0-9]*x[0-9]*.png) ;; *) mv "$f" "${f%.png}-$(magick identify -format %wx%h "$f").png" ;; esac
done
```

## Product page header and search results

App Store Connect's optional creative assets (Apple's
[specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
and [best practices](https://developer.apple.com/app-store/asset-best-practices/)),
in `marketing/`:

| File | Size | Use |
|------|------|-----|
| `universal-5244x2950.png` | 16:9 | one asset for both places (PNG only) |
| `header-3840x1646.png` | 21:9 | product page header |
| `search-3840x2560.png` | 3:2 | search results (iOS/iPadOS 27 and later) |

One design, "Read it. Run it." beside the app's own code card with real
output (the three lines print exactly that on Raku++ and Rakudo). Everything
that matters sits inside both the header's 21:9 band and the search image's 3:2
column of the universal image. All three are opaque, with no prices, URLs or
other platforms. Edit `marketing/hero.html` and run `marketing/render.sh`
(headless Chrome + ImageMagick). Check them in App Store Connect's Preview,
which shows where the store's own app name and button overlay the header.

## App Privacy answers (App Store Connect › App Privacy)

Answer **"Data Not Collected."** Rationale:

- The app has no backend and no analytics. It reads bundled JSON assets.
- `shared_preferences` stores theme choice, reading progress and Playground
  drafts **on device only**.
- The bundled Raku++ engine runs programs on the device; nothing is uploaded.
  It has no TLS of its own (HTTPS in Raku++ goes through the system OpenSSL,
  which iOS does not have), so `ITSAppUsesNonExemptEncryption` is `false` in
  Info.plist and App Store Connect will not ask about export compliance.
- `url_launcher` opens external links (e.g. Raku docs) in the system browser;
  no data is sent by the app itself.
- No account, no ads, no third-party SDKs, no tracking, no IDFA.

## Submission checklist

- [x] Bundle ID set to `online.deepsoft.learnraku` (Runner target, all configs)
- [x] Universal iPhone/iPad build
- [x] Listing text (name, subtitle, promo, description, keywords, what's new)
- [x] Support / marketing / privacy URLs live on deepsoft.online
- [x] Screenshots for the required 6.1"/6.3" iPhone slot (1206 × 2622) and 13" iPad, plus optional 6.9" and 6.5" sets
- [x] App Privacy = Data Not Collected
- [ ] Register the App ID `online.deepsoft.learnraku` in the Apple Developer portal
- [ ] Create the app record in App Store Connect and upload a build (Xcode / Transporter)
- [ ] Set the signing team for a release build (`DEVELOPMENT_TEAM` is currently `XEWRQ29E5N`)
- [ ] Provide a 1024×1024 marketing icon (App Store Connect; source at `assets/icon/app_icon.png`)
- [ ] Fill App Review contact phone number (`metadata/review_information/phone_number.txt`)
- [ ] Complete the age-rating questionnaire (all "None" → 4+)

## Notes / decisions

- Android `applicationId` was **not** changed. The Play Store namespace for this
  publisher's other apps is `com.deepsoft.*`, and Play package names are permanent
  once published — decide that separately before shipping Android.
- The screenshot harness pumps each screen directly (deterministic) rather than
  tapping through live navigation. Progress is pre-seeded so the home screen shows
  realistic stats and a "Continue" card.
