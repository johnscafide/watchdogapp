# Apple release handoff

This is the remaining Apple-side work, not a record of completed release certification. The app has not been compiled, run, signed, archived, uploaded, or reviewed by Apple in this Windows environment.

## Build and inspect

1. Use a Mac with full Xcode 16+ and iOS 17+ simulator runtimes. Open `Watchdog.xcodeproj` and run `bash Scripts/verify-macos.sh`.
2. Resolve any build errors or failed tests. Inspect the attached test screenshots in `.xcresult`, then manually walk through live search, property detail, sources, notes, map area search, denied location, lost network, save/relaunch, export/import, and town comparison.
3. Review small iPhone screens, iPad portrait/landscape, iPad split view, dark mode, VoiceOver, largest Dynamic Type, and Reduce Motion. Automated tests do not certify these visual/accessibility conditions.
4. Test URLSession against the live services on a real Apple device. The recorded Node probes establish endpoint contracts but do not establish device networking behavior or an availability SLA.
5. Verify the Release build opens live records and hides Debug sample settings. No sample or generated image should appear as an actual property report.

## Identity and App Store Connect

- Choose your final bundle identifier and Apple signing team. These belong to your Apple Developer account; no signing credentials are embedded.
- Create the App Store Connect app named Watchdog, set version/build numbers, and review device-family support.
- The opaque 1024px icon is included; inspect it on a device and replace it from the editable brand source if desired.
- Record actual app screenshots on supported iPhone and iPad sizes. Do not upload conceptual images as screenshots of a tested app.
- Prepare a support URL, app description, category, age rating, copyright, and accessible privacy-policy URL. Use current App Store Connect requirements when uploading.
- Archive for a physical iOS destination, validate the archive, distribute to TestFlight, and run a real-device acceptance pass before App Review.

## Privacy and external links

The included privacy manifest declares app-functionality use of search history and location because public-provider requests include searched text and, for nearby search, coordinates. It declares the app-owned UserDefaults required-reason API (`CA92.1`) and no tracking. Reconcile these declarations with the **actual providers’ collection/retention behavior** and your published privacy policy before submitting App Store privacy answers. Local notes and exports are not sent to Watchdog by this implementation. No advertising, analytics, or account SDK is installed.

Near me requests foreground permission only. Manual search remains available if denied. A MapKit basemap may use Apple services independently of parcel-source requests. No background location, notifications, photo-library, or microphone permissions are requested.

The consumer app’s Watchdog Pro section opens the existing professional website and does not unlock native paid content. Review Apple’s current rules for **each intended storefront** before shipping a subscription-related external link. The centralized `AppConfiguration.showsProWebsiteLink` flag can hide that link while retaining the separate-app coming-soon message. Do not infer worldwide approval from a US storefront rule. If native paid features are added later, reassess StoreKit, entitlements, restoration, and subscription rules.

This app does not create accounts; therefore no account deletion flow is currently needed in the binary. Adding account creation/sync later requires a complete lifecycle, including deletion and session/security handling.

Primary Apple references: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [App privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files), and [TestFlight](https://developer.apple.com/testflight/). Recheck these at submission time.

## Coverage to represent accurately

Describe this version as **New Jersey public property research**. It does not provide current MLS listing status, owner names, guaranteed market values, verified complete sales histories, tax appeal decisions, or tax benefit eligibility. Saved libraries are on-device, with user-driven Files backup/restore. Push alerts and automatic cloud sync are not implemented.
