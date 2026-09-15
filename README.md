# Watchdog for iPhone and iPad

An editable, native **consumer Watchdog app**, built with SwiftUI, MapKit, Charts, and Foundation. There is no embedded website, JavaScript application, or third-party mobile framework. The app is free to research public New Jersey properties without an account.

**Delivery status:** source implementation and portable checks are complete. Six live public API contract checks passed on September 14, 2026. This project was authored on Windows, which has no Apple SDK or Xcode; an Apple build, simulator/device run, visual review, and App Store acceptance have **not** been performed. Run the included Mac verification before treating the binary as release-ready.

## Open the app

1. Copy this entire `WatchdogNative` folder to a Mac with **Xcode 16 or newer** and an iOS 17+ simulator runtime.
2. Open **`Watchdog.xcodeproj`**. The local `WatchdogCore` package resolves from the included folder; no third-party Swift dependencies or package generator installation is needed.
3. Select the **Watchdog** scheme and an iPhone or iPad simulator. Press **Run**.
4. To explore fictional records without relying on public property APIs, select the **Watchdog Sample** scheme. Sample status is visible throughout. Public and sample libraries are separate.
5. For a physical device, select your Apple development team under **Watchdog → Signing & Capabilities** and use a bundle identifier your team owns. The starting identifier is `com.watchdogindex.consumer`.

Release builds always start with live public records. The sample switch and sample launch path are available only in Debug.

## What is built

| Area | Native functionality |
| --- | --- |
| Explore | Address/town/parcel/block-and-lot search, debounced queries, map and list views, nearby search, map-center search, recent and saved searches, assessment/class/score filters, sorting, empty/error/retry states |
| Property record | Public assessment and billed tax, source-specific years, land/improvement values, latest deed when supplied, municipal ratio, assessment-implied value, canonical score evidence when available, parcel outlines, sources, private notes, save/compare, Apple Maps directions |
| My Watchdog | Consumer research hub, saved-home summaries, quick access to research, comparisons, and understandable assessment explanations |
| Saved | Persistent device library, saved searches, removal, reopening and refreshing properties, up to four-property comparison |
| Towns | Searchable 564-town live directory, county filter, certified ratios, up to four-town comparison, source references, search properties in a selected town |
| Sharing | Native PDF dossier, text summary, system share sheet; private notes are excluded from property reports |
| Your library | Protected local storage, JSON backup export/import through Files, conflict-preserving note merge, explicit clear-data control, offline access to saved records |
| iPhone & iPad | Native phone tab bar, iPad sidebar and map/result layout, Dynamic Type, VoiceOver labels, dark mode, reduced-motion support, standard keyboard and sheet interactions |
| Watchdog Pro | A clearly separate coming-soon product and link to the professional website; no professional tools or paid feature unlocking in this consumer binary |

## Edit any code, anytime

Every source file is included as ordinary text. You can edit with **Xcode, VS Code, Codex, or another editor**. No generated-app subscription, proprietary editor, or external code host is required. Xcode on a Mac is required to compile and sign the iOS app; editing itself works on Windows.

| Change | Start here |
| --- | --- |
| Colors, typography, shared cards | `App/Design/WDTheme.swift`, `WDComponents.swift` |
| Search screen and map | `App/Explore/ExploreView.swift`, `ExploreMap.swift` |
| Property record, comparison, home hub, towns | `App/Features/` |
| Navigation and onboarding | `App/WatchdogApp.swift`, `WelcomeView.swift` |
| Saved data, request coordination, app state | `App/AppStore.swift` |
| Settings, research guide, Pro website link | `App/SettingsView.swift` |
| Public data endpoints and publishable client key | `WatchdogCore/Sources/WatchdogCore/PropertyService.swift` |
| Search matching and source decoding | `WatchdogCore/Sources/WatchdogCore/Search.swift`, `SourceDecoding.swift` |
| Data types and sample records | `WatchdogCore/Sources/WatchdogCore/Models.swift`, `SampleData.swift` |
| Editable icon and native brand mark | `App/Brand/watchdog-app-icon.svg`, `WatchdogEmblem.swift` |
| Apple metadata and privacy declarations | `App/Info.plist`, `App/PrivacyInfo.xcprivacy` |

Existing files are directly editable in the Xcode project. After **adding or removing** Swift files, run `python3 Scripts/generate-project.py` to update the checked-in project. The generator only writes the Xcode project, never your Swift code. Change build settings in the generator if you want them to survive regeneration.

## Verify on a Mac

From this folder:

```sh
bash Scripts/verify-macos.sh
```

The script runs portable checks, 24 core XCTest cases, 8 app-state tests and 4 consumer UI flows on available iPhone and iPad simulators, then builds Release for a simulator. Test results and screenshots are retained in `build/*.xcresult`. The test code is included but was not executed in the Windows authoring environment. If Xcode reports compilation or test failures, resolve them before signing or distributing.

Additional commands:

```sh
swift test --package-path WatchdogCore
node WatchdogCore/Scripts/public-api-smoke.mjs
python3 Scripts/check-source.py
```

The portable checker can optionally parse Swift syntax with `tree-sitter==0.26.0` and `tree-sitter-swift==0.7.3`; parsing is not type checking. The included GitHub workflow runs the Mac script after this folder is placed at a repository root. It has not been pushed or executed remotely.

## Data coverage and limits

Live research currently covers **New Jersey**. The public services are the same sources traced through your `johnscafide/njtaxrelief` repository. The app projects location fields carefully and excludes owner names and owner-mailing fields. A supplied publishable Supabase client identifier is included; no secret or service-role key is included.

The parcel layer does not provide every field Watchdog may have in its broader web platform. Full assessment/deed histories, licensed listings/photos, beds/baths, valuations, and tax relief eligibility calculations are not invented. Missing effective tax/assessment years remain unknown. The current live dossier includes only evidence provided by the connected services. An absent Watchdog Score is shown as unavailable, not zero. Search returns a bounded first 200 records; narrower queries improve precision.

Saved records and notes are **local to the device**, with Files backup/restore for moving research. Automatic account/cloud synchronization, remote change alerts/push, professional tools, and subscriptions inside the app are not enabled. This version does not create user accounts or modify the production database.

See [the data package guide](WatchdogCore/README.md), [architecture](Docs/ARCHITECTURE.md), [verification status](Docs/VERIFICATION.md), and [Apple release checklist](Docs/APPLE-RELEASE.md).

The native brand mark derives from Watchdog’s existing repository SVG. The forest/ivory theme is a native consumer design direction and can be changed centrally. Watchdog remains the master brand; Watchdog Pro is a future separate professional app.
