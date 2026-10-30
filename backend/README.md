# Bank Track community server

The app's Community runs on the phone today: profiles, sellers, bets for sale
and free bets are simulated there, and tokens and the pro bettor challenge are
stored on the phone, where they can be edited. This server is what makes the
community real.

## Why a server

- **Shared profiles, follows and free bets.** Another bettor's profile, their
  followers and the free bets they post have to live somewhere every phone can
  read. One phone can't see another.
- **Bets for sale.** The pick of a bet for sale must stay hidden until it is
  bought. If the pick were sent to every phone, anyone could read it without
  paying; the server sends it only to the seller and the buyers.
- **Tokens.** A balance kept on the phone can be edited. The server keeps a
  ledger (every credit and spend is a row) and moves tokens from buyer to
  seller in one transaction. Buying tokens with real money needs the server
  too: Google Play purchases must be verified on a server before tokens are
  given.
- **The pro bettor challenge.** Passing it lets a bettor sell, so it can't be
  decided on the phone. The server takes the 30 bets (odds over 1.60, before
  kick-off, no changes), settles them from ESPN's final scores and decides the
  pass or the week's wait.
- **Later:** notifications when someone you follow posts a free bet, reports
  and moderation, and keeping the Claude API key off the phone.

## Why Spring Boot

Spring Boot fits the parts that need care: the token ledger and purchases in
database transactions, a scheduled job that settles bets, and JWT sign-in
through Spring Security. It runs as one container on any host.

Alternatives considered: Supabase or Firebase alone would be quicker for
profiles and feeds, but the challenge, settlement and token moves would end up
in database functions or cloud functions spread across services. Serverpod
(Dart) would share code with the app but has a smaller ecosystem for
payments and jobs. Spring Boot plus a managed Postgres and Firebase
Authentication for sign-in keeps the rules in one tested codebase.

## What's here

- `domain/`: profiles, follows, bets (FREE, SALE, CHALLENGE), purchases, the
  token ledger, and `ChallengeRules`, the same rules as
  `lib/logic/community.dart`.
- `service/`: `CommunityService` (profiles, follows, free bets at 3 a day,
  selling for pros only, buying), `ChallengeService`, `TokenService`
  (10 welcome tokens, as the app gives), `SettlementJob` every 10 minutes with
  `EspnScoreProvider`.
- `web/CommunityController`: the API below. Refusals come back as
  `{"error": "..."}` with the text the app shows.
- `db/migration/V1__community.sql`: the schema (Flyway).

| Call | What it does |
| --- | --- |
| `GET /api/me`, `POST /api/profiles`, `PATCH /api/me` | The user's community profile and tokens |
| `GET /api/profiles/{handle}`, `PUT`/`DELETE .../follow` | A bettor's profile; follow and unfollow |
| `GET /api/feed/hot`, `GET /api/feed/sale` | Bets for sale, most bought first; the pick is hidden until bought |
| `GET /api/feed/free` | Free bets, from bettors you follow first |
| `POST /api/bets/free`, `POST /api/bets/sale`, `POST /api/bets/{id}/buy` | Post a free bet, sell (pros only), buy |
| `GET /api/challenge`, `POST /api/challenge/accept`, `/bets`, `/restart` | The pro bettor challenge |
| `GET /api/tokens` | Token balance |

## Live alerts with the app closed (Web Push)

The web app on iPhone (added to the Home Screen, iOS 16.4 or later) only runs
while it's open, so the alerts for kick-off, goals and full time come from
here, by Web Push, the way Safari delivers notifications to a closed web app.

- The bets stay on the phone. The app sends the server its push subscription
  and the matches with open bets (next 7 days, ESPN leagues), when it opens
  and whenever they change: `PUT /push/devices`. No sign-in: a phone is known
  by its subscription.
- `LiveAlertJob` reads ESPN's summary for each followed match from 30 minutes
  before kick-off and sends what changed, with the same rules and texts
  (English and Spanish) as `lib/logic/live_alerts.dart`.
- `WebPush` encrypts each message for the browser (RFC 8291) and signs it with
  the server's VAPID key (RFC 8292), plain JDK crypto. The key pair is made on
  first start and kept in `push_keys`; `GET /push/key` hands out the public half.
- Cloud Run sleeps between requests, so a Cloud Scheduler job calls
  `POST /push/tick` every minute (header `X-Tick-Key`, the `PUSH_TICK_KEY`
  setting). Elsewhere the job also runs on its own timer.
- Subscriptions Apple or Google say are gone, and phones silent for 30 days,
  are dropped.

| Call | What it does |
| --- | --- |
| `GET /push/key` | The public key to subscribe with |
| `PUT /push/devices` | `{subscription, lang, matches}`: save the phone and the matches it follows |
| `DELETE /push/devices` | `{endpoint}`: alerts switched off |
| `POST /push/tick` | Run a round now (Cloud Scheduler) |

## Deploy (Google Cloud Run + Neon)

`.github/workflows/backend-deploy.yml` deploys on every change to `backend/`
on main, or by hand from Actions > Deploy server > Run workflow. After it, the
web app is rebuilt and finds the server by itself. It needs two repository
secrets (Settings > Secrets and variables > Actions):

1. **`DATABASE_URL`**: at neon.tech, create a project (free), then copy the
   connection string from Connect (`postgresql://...?sslmode=require`).
2. **`GCP_SA_KEY`**: in a Google Cloud project with billing on
   (console.cloud.google.com; light use stays in the free tier, a budget
   alert at $10 is a good idea):
   - IAM & Admin > Service Accounts > Create, name `github-deploy`, with the
     roles Cloud Run Admin, Cloud Build Editor, Artifact Registry Administrator,
     Storage Admin, Service Account User, Cloud Scheduler Admin and Service
     Usage Admin.
   - Open it > Keys > Add key > JSON, and paste the whole file as the secret.

## Sign-in

Every `/api` call needs a Firebase Authentication ID token
(`Authorization: Bearer ...`); its subject is the user id. Set
`AUTH_ISSUER_URI=https://securetoken.google.com/<firebase-project-id>`.
For local runs, `DEV_AUTH=true` lets the `X-Dev-User` header name the user
instead. Never set it in production.

## Run it

```
cd backend
mvn test                     # rules and a full API run on an in-memory database
docker run -e POSTGRES_USER=banktrack -e POSTGRES_PASSWORD=banktrack -e POSTGRES_DB=banktrack -p 5432:5432 postgres:17
DEV_AUTH=true mvn spring-boot:run
curl -H 'X-Dev-User: laura' -H 'Content-Type: application/json' \
  -d '{"handle":"laura_bets","name":"Laura"}' localhost:8080/api/profiles
```

Settings: `DATABASE_URL` (JDBC), `DATABASE_USER`, `DATABASE_PASSWORD`,
`AUTH_ISSUER_URI`, `PORT`.

## Still to do before going live

- Hosting and accounts: a Firebase project (sign-in), a Postgres database and
  a container host.
- Connect the app: sign in with Firebase, then call this API from
  `lib/ui/community.dart` in place of the simulated data.
- Google Play Billing: verify token purchases here and credit them to the
  ledger (`reason = PLAY_STORE`, the order id as the reference, so an order
  can't be credited twice).
- Check the odds of challenge bets against an odds source on the server,
  instead of trusting the price the app sends.
- Decide the house cut on bet sales (today the seller gets the full price).
