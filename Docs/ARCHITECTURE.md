# Native consumer architecture

The project separates Apple presentation, local app state, and portable data access. There are no web views, remote UI bundles, paid gates, or SDK secrets.

```text
WatchdogApp / RootView
  ├─ ExploreView + MapKit + one-shot CoreLocation
  ├─ HomeView / SavedView / CompareView / AtlasView
  ├─ PropertyDetailView → Charts, parcel outlines, local notes, PDF sharing
  └─ SettingsView → appearance, Files backup/restore, methodology, Pro link
            │
      AppStore (@MainActor + @Observable)
        ├─ versioned device archive, distinct live/sample libraries
        ├─ search and detail generations reject stale responses
        └─ PropertyService protocol
             ├─ WatchdogPropertyService actor
             │    └─ URLSession HTTPTransport → NJ GIS / Watchdog public sources
             └─ SamplePropertyService → explicit fictional fixtures
```

## Data boundaries

`PropertyRecord` distinguishes source figures, source dates, calculated assessment-implied value, and Watchdog-derived score metadata. Coordinates are optional. Parcels are identified by the source PAMS PIN, and optional enrichment must match that identity. Address geocoding is a fallback with confidence and address-type checks. It cannot convert a town or ZIP centroid into an arbitrary home match.

`WatchdogPropertyService` is a Foundation actor, and requests go through injectable `HTTPTransport`. Optional score/ratio failure leaves explicit missing evidence; primary parcel failure returns an error. Public lookup requests are bounded, encoded, and projected to specific fields. The service does not return owner identities and cannot request a sample record as live detail. Existing public POST endpoints are read operations.

Town ratios and property tax/assessment years remain separate. A current retrieval timestamp never turns an old record into a current tax bill. Full historical data needs another verified source implementation, not a change to the user interface.

## Local state and persistence

`AppStore` owns observable UI state. A new text query invalidates old results immediately. Generation IDs prevent a slower, older request from replacing newer results. `searchIfNeeded()` prevents a late debounce or view re-entry from replacing an active map search. `retrySearch()` preserves the requested map center.

Saved data is an atomic JSON archive under the app’s Application Support directory, using iOS complete-until-first-authentication file protection. Live and sample records have separate archive entries. Notes stay on device and are excluded from report sharing. Backup imports are bounded to 20 MB and merge without overwriting existing local notes. An unreadable archive is preserved until the user explicitly resets or replaces it through import.

Local storage may be included in the operating system’s device backup, according to the user’s settings. There is no implemented Watchdog server synchronization or account association. Do not label saved items as cloud-synced or alerts as active without adding those services.

## Apple presentation

iPhone uses tabs and native navigation stacks. iPad uses a sidebar; Explore splits results and MapKit when width permits. Property dossiers use native sheets. Charts require actual observations; missing histories have clear source states. Approximate parcel outlines are MapKit overlays, not surveys.

Theme colors adapt to light and dark mode. Headings use the system serif design and body text uses system typography. Dynamic Type controls switch dense layouts where possible. Motion changes honor Reduce Motion. Location permission is requested only after tapping Near me; there is no background location capability.

## Editing and extending

All Swift code is checked into the deliverable. The Python Xcode generator records the file list and targets; it does not generate view implementation. The app uses only Apple frameworks and the included package.

To add broader geographic coverage, implement `PropertyService` with licensed/public provider contracts and geographic metadata. To add synced accounts later, introduce a separate authenticated repository, Keychain session storage, verified account identity, row-level ownership rules, conflict resolution, and account deletion. Keep device-only browsing available.

Professional workflows belong in **Watchdog Pro**, a separate application. Shared models can be reused; selecting a role must never grant entitlements. Do not add subscription checkout or change the existing production `live_billing_lifecycle` gate from this consumer project.

## Repository and source references

The user-provided repository was inspected at `f9ec6a348b0f7590f798a8d75ab0a3ce9010511f`. Integration and brand rules follow its `AGENTS.md`; no source files, Supabase settings, billing configuration, or remote branches were changed. Historical Linear mobile discussion (NJW-56) concerned earlier agent web workflows; the user’s current consumer-native request controls this build.

Watchdog links use `https://www.watchdogindex.com` and clean public paths. `NJPropertyTaxRelief.com` remains a separate existing site. The iOS URL scheme accepts bounded `watchdog://search?q=...` requests; universal links would require a separately deployed association file and team identifiers.
