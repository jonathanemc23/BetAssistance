# Bank Track (mobile MVP)

Flutter app for tracking a betting bankroll. Android first; the same code can
target iOS later.

## What's in it

- **Bets screen**: bankroll card (balance, available after open bets, deposit
  and withdraw, history), stat tiles (profit/loss and units, ROI, win rate,
  number of bets, average odds, money at risk), and the bet register with
  filters, one-tap Won/Lost settling and a form to log or edit a bet.
- **Charts screen**: bankroll over time, profit by month, results breakdown,
  profit and ROI by sport.
- **Settings**: starting bankroll and date, unit size, currency, decimal or
  American odds.

The data model and the stat rules are the same as the web version
(ROI = profit / settled non-void stakes; win rate counts won and lost bets only).

## Data safety between releases

Data lives in a SQLite database (`bank_track.db`) in the app's private storage.
Android keeps it when a new version is installed over the old one, as long as:

1. **The applicationId stays `com.banktrack.app`.** Changing it makes a new,
   empty app.
2. **Every release is signed with the same key** (`android/app/banktrack-release.jks`,
   passwords in `android/key.properties`). A build signed with a different key
   cannot be installed as an update; the user would have to uninstall and lose
   their data. Back these two files up somewhere safe and never commit them.
3. **Schema changes go through migrations.** `lib/data/database.dart` keeps a
   list of migrations; each release that changes the schema appends one entry
   (additive changes only, never edit or delete an old entry). A failed
   migration rolls back and leaves the old data intact, and an older app
   refuses to open a newer database instead of wiping it. `test/database_test.dart`
   covers all of this.

The database is also included in Android's own backup and phone-to-phone
transfer (`android/app/src/main/res/xml`).

## Running

```sh
flutter pub get
flutter test                # stats, database and screen tests
flutter run                 # on a connected Android phone or emulator
flutter build apk --release # APK at build/app/outputs/flutter-apk/app-release.apk
```

Bump `version:` in `pubspec.yaml` (e.g. `0.1.1+2`) for each release; the
number after `+` must go up for Android to accept the update.

`SCREENSHOTS=1 flutter test test/app_test.dart --update-goldens` regenerates the
screenshots in `test/screenshots/`.

## CI

`.github/workflows/android.yml` analyzes, tests and builds the APK on GitHub.
To sign CI builds with the release key, add two repository secrets:
`KEYSTORE_BASE64` (`base64 -w0 android/app/banktrack-release.jks`) and
`KEY_PROPERTIES` (the contents of `android/key.properties`).
