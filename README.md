# Bank Track (mobile MVP)

Flutter app for tracking a betting bankroll. Android first; the same code can
target iOS later.

## What's in it

- **Home** (main page): avatar and name (picked in Settings or by tapping
  the avatar), the bank with highlights (open bets, money at risk, profit,
  ROI), the day's important matches in a sideways strip, Pro tips and free
  tips for those matches. "See summary" opens the full summary.
- **Pro tips** (Bet Tools, Home, or a match page): simulated predictions.
  The odds follow the price: free tips 1.40-2.00, Max (3 tokens)
  1.80-2.00, High (2) and Medium (1) 1.60-2.00, as a single or two
  selections together (`followsOddsRules` in `lib/logic/pro_tips.dart`).
  The day's page lists tips for the important matches and has a match search.
- **Stake builder** (inside Bet Tools): goals, corners, cards,
  shots and fouls over each team's last six games, read from ESPN's box
  scores (`FixturesApi.stakeStats`). Pick over/under lines from one or more
  matches; Validate checks each pick by its hit rate before kick-off and by
  the match's own stats once it starts (`lib/logic/stake_stats.dart`).
- **NBA pro tip** (top of the Stake builder, locked, 6 tokens): reads the
  day's NBA games and builds 2 or 3 player lines ("20+ points: Kevin
  Durant") from each team's leaders, total odds 2.40 to 3.70
  (`lib/logic/nba_stake.dart`). Lines are random for now, each set under the
  player's season average to match its price. With no game left to start
  the button reads "No NBA matches today, try again tomorrow" and takes no
  tokens. Pro tips settle from ESPN's box score and log as a parlay.
- **Automatic results**: `lib/data/bet_settler.dart` puts in the result of
  open bets once their match is over: singles and parlay legs picked from
  the Matches list (legs now keep their match), Parlay builder parlays,
  community bets (challenge, bought, for sale, free bets) and NBA pro tips.
  Markets the score can't settle (corners, cards, scorers) stay for the
  user. It runs when the app starts, after each full time and every 10
  minutes, and sends a "Bet won/lost" notification when alerts are on.
- **Community** (side menu, under Bet Tools): a community profile is needed
  to join. The community page has a Become a pro bettor button on top (how
  the challenge works and its requirements: 30 bets that can't be changed,
  each with odds over 1.60, 60% to pass, a week's wait after a fail or a
  restart, restart allowed from 10 bets), then the hottest bets to buy with
  tokens, then free bets bettors post to gain followers (follow them, or post
  up to 3 of your own a day; `lib/logic/community.dart`). In the app,
  profiles, sellers and their bets are still simulated on the phone; the
  server that shares them is in `backend/` (see below).
- **Languages**: English and Spanish, picked in Settings (the phone's
  language by default). Every text goes through `tr()` in `lib/l10n/`;
  `test/l10n_test.dart` fails when a text has no Spanish.
- **Summary**: bankroll card (balance, available after open bets,
  deposit and withdraw, history), stat tiles (profit/loss and units, ROI, win
  rate, number of bets, average odds, money at risk) and bets per type.
- **Bets**: the bet register with filters, one-tap Won/Lost settling, and a
  long-press menu to edit, share or log a bet again.
- **Log a bet**: sectioned form with bet type (single, parlay, system, other),
  parlay legs with their own odds and results (combined odds and the parlay's
  result are worked out from the legs), unit stake shortcuts and a live
  returns bar.
- **Matches**: football, basketball and baseball fixtures for a country on
  any day, from ESPN's free public scoreboard feed (no key) and TheSportsDB's
  free feed. Country list and league slugs are in `lib/data/fixtures.dart`;
  tap a match to log a bet on it, or pick one from the bet form. A country's
  ESPN leagues show first while TheSportsDB's (free key: about 30 requests a
  minute, two thirds kept for what's on screen) are still coming, and a new
  tap drops the requests of the one before. Live football is one request to
  ESPN's all-leagues scoreboard (league ids in `lib/data/espn_leagues.dart`).
  Favorites fill in each league's scores as they arrive. Leagues without a
  table in ESPN's match summary get one from ESPN's standings feed (the
  latest stage that has one), and TheSportsDB leagues (Cyprus, Ecuador's
  Serie B) get a table, form and meetings worked out from the season's rounds.
- **Share links**: a bet is encoded in the link itself
  (`https://jonathanemc23.github.io/BetAssistance/b/#<code>`). The page shows
  the bet and opens it in the app pre-filled; the app also opens
  `banktrack://bet?d=<code>` links and pasted links (link icon on the Bets tab).
  The page is published by `.github/workflows/pages.yml` from `web/`; GitHub
  Pages must be enabled with source "GitHub Actions".
- **Live alerts**: Android notifications on kick-off, every goal (score
  change) and full time for matches in pending bets picked from Matches and
  in open parlays' linked legs. `lib/data/live_alert_service.dart` reads
  those matches from the feed once a minute while the app runs (open or in
  the background until Android stops it); `lib/logic/live_alerts.dart`
  decides what to say. Switch it off in Settings.
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
On `main`, once the signing secrets below exist, it also publishes a GitHub
release named after `version:` in `pubspec.yaml` with the signed APK attached.
Without the secrets it builds a debug-signed APK as a CI check only; don't
install that on a real phone, since later signed releases can't update it.
To sign CI builds with the release key, add two repository secrets:
`KEYSTORE_BASE64` (`base64 -w0 android/app/banktrack-release.jks`) and
`KEY_PROPERTIES` (the contents of `android/key.properties`).

## Community server (`backend/`)

Spring Boot 4 (Java 21) with PostgreSQL. It holds what can't live on one
phone: shared profiles and follows, free bets and bets for sale, the token
ledger, and the pro bettor challenge, settled from final scores on the server
so nobody can fake a pass. See [backend/README.md](backend/README.md).
