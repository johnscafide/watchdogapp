# Run Watchdog in Appetize

This project contains a GitHub Actions workflow that builds the iOS Simulator `.app` bundle required by Appetize and packages it as `Watchdog-Appetize.zip`.

## Build without owning a Mac

1. Create a GitHub repository for this project (for example `watchdog-ios`).
2. Put the **contents of this folder at the repository root**. The repository root should contain `App/`, `WatchdogCore/`, `Watchdog.xcodeproj/`, `Scripts/`, and `.github/` directly.
3. Push to GitHub.
4. Open the repository's **Actions** tab.
5. Select **Build Watchdog for Appetize**.
6. Choose **Run workflow**.
7. When it succeeds, open the workflow run and download the artifact named **watchdog-appetize-ios**.
8. GitHub downloads artifacts as a ZIP wrapper. Extract that wrapper once. Inside is **Watchdog-Appetize.zip**.
9. Upload **Watchdog-Appetize.zip** to Appetize as an iOS app.

Do not upload an `.ipa`; Appetize needs the simulator `.app` bundle packaged in ZIP/tar.gz form.

## Live vs sample demo

The generated Debug simulator build starts in normal/live mode by default. Watchdog also supports a built-in sample-data mode in Debug. Appetize supports iOS launch arguments, so a demo session can be launched with the argument:

`--sample-data`

The normal live build is better for testing current public Watchdog data. Sample mode is useful for a deterministic sales/demo walkthrough if network data is unavailable.

## Local Mac alternative

On a Mac with Xcode installed, run:

```sh
bash Scripts/build-appetize.sh
```

Then upload:

`build/appetize/Watchdog-Appetize.zip`
