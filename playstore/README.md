 # Google Play submission kit — Learn Raku

Everything needed to create the Google Play listing for **Learn Raku**
(the Course of Raku by Andrew Shitov, offline). Numbers are generated from the
bundled content so they stay accurate.

## App identity

| Field | Value |
|-------|-------|
| App name | **Learn Raku** |
| Application ID | **online.deepsoft.learnraku** (matches the iOS bundle ID) |
| Version / build | 1.0.0 (versionCode 3) — from `pubspec.yaml` `version:` |
| Android | 7.0+ (minSdk 24), targetSdk 36; native engine for arm64-v8a, armeabi-v7a, x86_64, 16 KB-page aligned |
| Form factors | Phone + tablet (Flutter universal) |
| Category | Education |
| Content rating | Everyone (no objectionable content) |
| Price | Free |

The application ID and `namespace` are set in
[android/app/build.gradle.kts](../android/app/build.gradle.kts); `MainActivity.kt`
was moved to `online/deepsoft/learnraku/`.

## Listing text & assets

Stored in the [fastlane `supply`](https://docs.fastlane.tools/actions/supply/)
layout under `metadata/android/en-US/`, so it can be pushed with
`fastlane supply` or pasted into the Play Console by hand:

```
metadata/android/en-US/
  title.txt               Learn Raku            (≤30)
  short_description.txt    (≤80)
  full_description.txt     (≤4000)
  changelogs/1.txt         "What's new" for versionCode 1 (≤500)
  images/
    icon.png               512×512 (Play applies its own mask)
    featureGraphic.png      1024×500 (required)
    phoneScreenshots/       captured from the app (see below)
```

Store URLs (same pages serve both stores):

- Privacy policy: https://deepsoft.online/policy/learn-raku
- Support / website: https://deepsoft.online/support/learn-raku and /mobile/learn-raku

## Screenshots

Captured from the app on a Pixel 7 emulator (Android 15, the `Pixel_7_API_35`
AVD) via the integration-test harness — the same one used for iOS, with the
Android path calling `convertFlutterSurfaceToImage`. The run screenshots execute
real Raku through the bundled engine. PNGs are in
`metadata/android/en-US/images/phoneScreenshots/`, 1080 × 2160: the Pixel 7's
1080 × 2400 is cropped (150 px off the top, 90 off the bottom) because Play
rejects a screenshot whose long side is more than twice the short one.

To regenerate (emulator must be running):

```bash
flutter drive --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/screenshot_test.dart \
  -d emulator-5554 --dart-define=SS_DEVICE=android-phone
# then crop the first eight appstore/screenshots/android-phone/NN-*.png into phoneScreenshots/N.png:
#   magick 01-lesson-run.png -crop 1080x2160+0+150 +repage 1.png
```

Play takes **2 to 8** phone screenshots; this kit provides the first 8 of the
harness's 10, in store order (lesson run, input, playground, home, Final Test,
quiz, exercise, dark home) — search and the part browser are the two left out. A tablet
set is optional — capture on a tablet AVD with `SS_DEVICE=android-tablet` if you
want the "Designed for tablets" treatment.

## Data safety form (Play Console › App content › Data safety)

- **Data collected:** None.
- **Data shared:** None.
- No account, no ads, no analytics, no third-party SDKs, no advertising ID.
- `shared_preferences` keeps theme, reading progress and Playground drafts
  **on device only**; `url_launcher` opens external links in the browser.
  Neither transmits data.
- The bundled Raku++ engine runs programs on the device; nothing is uploaded.

## Signing

Release builds sign with the upload keystore `android/keystore/upload-keystore.jks`
(configured through `android/keystore.properties`; certificate
`CN=DeepSoft, OU=Mobile, O=DeepSoft, L=Riga, C=LV`). Let Play App Signing manage
the app signing key.

```bash
flutter build appbundle --release   # → build/app/outputs/bundle/release/app-release.aab
```

## Submission checklist

- [x] Application ID `online.deepsoft.learnraku` (build.gradle.kts + MainActivity moved)
- [x] App name / short / full description / changelog (within Play limits)
- [x] 512×512 icon and 1024×500 feature graphic
- [x] ≥2 phone screenshots
- [x] Privacy policy URL live on deepsoft.online
- [x] Data safety = no data collected / shared
- [x] Release **upload keystore** configured
- [x] `flutter build appbundle --release` (versionCode 2) — upload the `.aab`
- [ ] Complete the content-rating questionnaire (all "None" → Everyone)
- [ ] Set up the Play Console app, countries, and pricing (Free)

## Notes

- Screenshot harness lives in the app repo (`integration_test/screenshot_test.dart`
  + `test_driver/screenshot_driver.dart`) and is shared with the iOS kit under
  `appstore/`.
