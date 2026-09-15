# WatchdogCore

The editable, Foundation-only data package behind the native Watchdog consumer app. It has no third-party Swift dependencies and no web view. The public API is shared by iPhone and iPad.

## Run and edit

Open `Package.swift` in Xcode, or open the enclosing Watchdog app project. Change models in `Sources/WatchdogCore/Models.swift`, search behavior in `Search.swift`, data connections in `PropertyService.swift`, and fixtures in `SampleData.swift`.

On a Mac with Xcode's command-line tools selected:

```sh
swift test
```

The 24 XCTest cases use a fake `HTTPTransport`. They cover public field projection, unknown values, source failures, cancellation, score model and parcel identity, ratio district identity, source date decoding, geocoder quality, coordinate bounds, result truncation, duplicate records, batch limits, persistence, and sample/live isolation. They make no external requests.

The Windows authoring environment has no Swift compiler or Apple SDK. All 10 package Swift files passed a tree-sitter syntax parse; this does not replace compiling or running XCTest. Execute the tests and the enclosing app's simulator/device checks on macOS before release.

## Live connection

`WatchdogPropertyService()` uses the current public Watchdog and New Jersey contracts. It does not require a Watchdog account. `WatchdogServiceConfiguration` lets you replace each endpoint and inject a publishable client key. `HTTPTransport` permits deterministic tests or a custom URLSession.

| Data | Existing public source | Behavior |
| --- | --- | --- |
| Parcel search, detail, approximate boundaries | NJ Office of GIS ArcGIS `Parcels_Composite_NJ_WM` | Address/town, exact PAMS PIN, block and lot, spatial search; first 200 results, with truncation notice |
| Address fallback | NJ geocoder | Only high-confidence address/intersection types; a town or ZIP centroid never becomes a property match |
| Municipal directory | Watchdog `/towns/town-manifest.json` | 564 districts in the live probe |
| Certified municipal ratio | Existing Supabase `chapter123-provider` | Single district and batches of at most 500; ratio year stays separate from property tax/assessment year |
| Watchdog Score | Existing public `get_public_property_watchdog_score_details` RPC | At most 100 parcel IDs per call; only `ROBUST-v1`, matching parcel ID and valid 0–100 score |

The shipped key is an existing **publishable** client identifier from Watchdog's public app. There are no service-role keys, secret keys, account tokens, schema changes, or remote writes. A publishable key is suitable for a shipped mobile client; see [Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys). The current Supabase changelog was checked on 2026-09-14; the native code uses Foundation HTTP rather than a Supabase SDK, and consumes existing exposed RPCs rather than creating tables.

Optional score and ratio outages preserve parcel records and explicitly show missing evidence. Parcel-source failures remain errors. A source outage **never** changes the data mode or substitutes sample data.

## Honest data boundaries

- The connected public parcel service currently covers **New Jersey**, not nationwide properties. A future national provider can implement `PropertyService` without replacing the native views.
- No owner name, owner mailing address, or owner-mailing ZIP is requested or modeled. `ZIP5` in this source is not used as the property's location ZIP.
- `NET_VALUE`, `LAND_VAL`, and `IMPRVT_VAL` are source assessments. `LAST_YR_TX` is the source's last-year billed tax. This feed does not supply their effective assessment/tax year; those years remain `nil` instead of being set to the current year.
- `updatedAt` is retrieval time. `sourcePublishedAt` is the source parcel publication timestamp when provided. Neither is presented as the effective tax year.
- The latest deed is available when both a source date and positive price exist. It is labeled as unverified for arm's-length usability. Full deed and assessment histories need a separate verified history source; live arrays remain empty when evidence is unavailable.
- Living area, listing status, current sale availability, interior condition, neighborhood ratings, effective municipal tax rates, median municipal assessments, and municipal Watchdog Scores are not fabricated from this feed.
- Assessment divided by the certified municipal ratio is an **assessment-implied value**, not an appraisal, offer price, market estimate, or appeal conclusion. A positive ratio can exceed 1 when the source certifies more than 100%.
- A missing canonical score stays missing. There is no alternate score formula or on-device simulated score. The live probe's sampled parcel returned an empty score array, which is valid.
- Approximate parcel geometry is not a survey or legal boundary. Device location is used only when the app requests it for nearby search.

## Explicit sample experience

`SamplePropertyService()` is entirely local. It contains 11 fictional parcels across six New Jersey towns, including an intentionally incomplete record for missing-data states. Every property and town is marked `isSample`; every property source states that its figures, location and address describe no real property. Sample IDs cannot be sent to live detail. No fictional Watchdog Score is generated.

## Bounded live verification

From this package directory, using Node 20 or later:

```sh
node Scripts/public-api-smoke.mjs
```

The script reads the actual Swift endpoint configuration, makes six bounded read-only contract probes, and writes `public-api-smoke.latest.json`. Its POST requests call existing read-only ratio/score APIs. It neither signs in nor creates data. The report excludes raw parcel records and client keys.

The 2026-09-14 run passed all six probes: parcel search with centroids, geocoder, 564-town manifest, Chapter 123 single and batch responses, and the canonical score RPC. These are Node HTTP checks, not native URLSession execution or Apple UI certification. Re-run when source contracts change and before publishing.

## Existing source references

Integration behavior was traced to the supplied `johnscafide/njtaxrelief` repository, including `property/js/lookup.js`, `supabase/functions/chapter123-provider/index.ts`, and `supabase/migrations/20260826214428_njw_270_public_robust_score_cache.sql`. The existing production Supabase project and NJPropertyTaxRelief coexistence settings were left unchanged. All user-facing Watchdog links use the canonical `https://www.watchdogindex.com` host and clean root-level paths.
