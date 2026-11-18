# Test matrix

Every feature, the cases it must handle, and where each case is checked.
**Auto** = covered by `flutter test` (file in `test/`); **Manual** = checked by
hand on a device before each beta build; **Gap** = not checked yet, with the
plan item that closes it (see the MVP plan).

Run on every case unless the row says otherwise: English and Spanish, phone
and web, a fresh install and an install with data.

Line coverage of `lib/` on 2026-11-18: 83% (`flutter test --coverage`).

| Feature | Cases | Auto | Manual | Gap |
| --- | --- | --- | --- | --- |
| Log a bet (form) | single, parlay with legs, system, other; odds decimal and American; unit shortcuts; edit and log again | `app_test.dart` | log one of each type on a phone | |
| Bet register | filters, one-tap Won/Lost, long-press menu, swipe | `app_test.dart` | | |
| Summary and stats | balance, available, profit, ROI, win rate, units, by type | `stats_test.dart`, `app_test.dart` | numbers match a hand count for 10 bets | |
| Charts | bankroll over time, by month, by sport, empty state | `app_test.dart` | | empty state with no bets |
| Deposits and withdrawals | amount above zero, comma decimals, note, delete by swipe | `core_flows_test.dart` | | withdrawing more than the balance is allowed: decide if it should warn |
| Settings | bankroll and unit refused when not a number, currency, odds format, language, theme | `core_flows_test.dart`, `app_test.dart` | | |
| Database and updates | migrations, rollback on a failed migration, newer database refused | `database_test.dart` | install the new build over the last release, data kept | |
| Screenshot import | Betano, Bet365, others; single and parlay; unreadable picture | `slip_reader_test.dart`, `slip_bet_test.dart` | 5 real slips per bookmaker on iPhone, Android and web | more bookmakers |
| Automatic results | singles, parlay legs, parlay builder, community bets, NBA pro tips; void; markets left to the user | `auto_settle_test.dart` | a real match day | iPhone with the app closed (only catches up on open) |
| Live alerts | kick-off, goal, full time; switched off | `live_alerts_test.dart`, `push_alerts_test.dart` | one real match on each platform | |
| Matches and match page | countries, days, leagues, live, table, line-ups, shot map, Players tab | `fixtures_test.dart`, `match_details_test.dart`, `app_test.dart` | | feed format changes (Q4) |
| Parlay builder and check | legs from matches, combined odds, warnings | `parlay_check_test.dart`, `leg_linker_test.dart`, `app_test.dart` | | |
| Stake builder (football) | stats of the last six games, picks from two matches, validate before and after kick-off | `stake_community_test.dart`, `app_test.dart` | | |
| NBA pro tip | lines from the day's games, odds range, no games today, settle from box score | `stake_community_test.dart`, `auto_settle_test.dart` | | real model (M1 to M6) |
| Pro tips (football) | odds follow the price, tokens spent and refunded | `pro_tips_test.dart` | | real model |
| Bet review | suggestions per bet type | `bet_review_test.dart` | | |
| Share links | link in the sheet, copy, paste a link or a message, refuse other text, `banktrack://` | `share_test.dart`, `core_flows_test.dart` | open a link from WhatsApp on each platform | |
| Account and sync | email sign-in, wrong password, refresh, two devices, choose which data to keep, sign-out clears the device | `account_sync_test.dart` | two phones, one account | account deletion (phase 4) |
| Community | sign-in gate, unique nametag, tabs, bettor profile, challenge rules | `stake_community_test.dart`, `app_test.dart`, backend tests | | real feeds, moderation (S1 to S8) |
| Matchboard and AI assistant | offline answers, Claude answers with a key | `assistant_test.dart`, `claude_assistant_test.dart` | | the screen can't be opened from the app since 0.15.0 |
| Avatars and themes | every preset person, photo, initial; every theme | `core_flows_test.dart`, `app_test.dart` | | |
| Languages | every text has Spanish | `l10n_test.dart` | read every screen in Spanish once per release | |
| Offline | each screen with no connection | | airplane mode on each tab | Q7 |
