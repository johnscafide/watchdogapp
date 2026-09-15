# Verification record

Checked September 14, 2026 in the Windows authoring workspace.

| Check | Result |
| --- | --- |
| All Swift sources parsed with tree-sitter Swift grammar | Passed; syntax only, not Swift type checking |
| JSON, Apple plist, privacy manifest parsing | Passed |
| Xcode OpenStep project parsing | Passed |
| App source membership in generated Xcode project | Passed |
| Opaque 1024px app icon | Passed |
| Embedded web-view / privileged-key pattern scan | Passed |
| NJ parcel and centroid response contract | Passed |
| NJ address geocoder response contract | Passed |
| Watchdog town manifest | Passed, 564 municipalities |
| Chapter 123 single and batch contracts | Passed |
| Public canonical Watchdog Score RPC | Passed; sampled property returned no score, preserved as unavailable |
| Core XCTest suite | 24 tests authored; not executed |
| App state XCTest suite | 8 tests authored; not executed |
| Consumer UI tests | 4 flows authored for iPhone/iPad; not executed |
| Apple SDK compilation / Release build | Not run; Xcode unavailable |
| Simulator/device visual and accessibility review | Not run |
| Signing, TestFlight, App Review | Not performed |

The reproducible live report is `WatchdogCore/public-api-smoke.latest.json`. It contains result metadata, no raw property addresses or client keys. `Scripts/check-source.py` reproduces the portable source checks. `Scripts/verify-macos.sh` performs the required Apple compilation and test passes on a Mac.

The source review checked out-of-order search responses, live/sample isolation, missing values/years, owner-mailing-field exclusion, score model/parcel matching, ratio district matching, request bounds, corrupt archive preservation, note import conflicts, native navigation, and Release sample-mode handling. It found and fixed the sample-mode upgrade issue, duplicate detail navigation, stale map search retries, and tests that reopened with non-isolated defaults.

The API checks were executed using Node’s HTTP implementation, not Swift’s URLSession. UI test assertions and screenshots have no recorded passing result until the Mac script runs. No claims of pixel-perfect rendering, crash-free behavior, performance superiority, or App Store approval are made by these checks.
