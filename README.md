# Keys Lite (Phase 1)

Resident app and API for Keys Lite, built from the *KEYS_Phase1_Requirements_Spec*
sheet and the Resident APP Figma files.

| Folder | What it is |
| --- | --- |
| `app/` | Flutter resident app (iOS, Android; web build used for checks) |
| `backend/` | API: Node 22, TypeScript, Fastify, PostgreSQL |
| `docs/` | Decisions taken during the build, report reasons, requirement coverage |

## Build status

| Milestone | Features | State |
| --- | --- | --- |
| 1 | Onboarding and login, Learning experience, Address verification, cross-feature foundations (media limits, reports, share links) | Done |
| 2 | Profile and settings, Feed, Polls | Next |
| 3 | Committee board, Voting | |
| 4 | Updates, Update chat, Chat | |
| 5 | Free events, Free clubs, Calendar | |

Requirement-by-requirement coverage: [`docs/coverage.md`](docs/coverage.md).

## Run the API

```bash
cd backend
npm install
cp .env.example .env        # works as is: every outside service is mocked
npm run migrate
npm run dev                 # http://localhost:3000
```

Needs PostgreSQL 14+ with the `pg_trgm`, `citext` and `pgcrypto` extensions
(all ship with Postgres), and `ffprobe` on the PATH for the video length check.

Tests run against a real database (`TEST_DATABASE_URL`, default
`postgres://keys@localhost:5433/keys_test`):

```bash
npm test
```

### Mock mode

| Service | Mock behaviour | Real service |
| --- | --- | --- |
| Email | Codes and emails are written to the `email_outbox` table | Resend |
| Address lookup | A small fake London neighbourhood (Maple Road, Oak Avenue, Elm Street...) plus one street in Brighton | Google Places (New) |
| Card address check | Payment method ids `pm_mock_pass_<brand>_<last4>` pass, `pm_mock_fail_...` fail. In the app, card numbers ending `0002` fail | Stripe SetupIntent, `address_line1_check` and `address_postal_code_check` must both pass |
| Apple / Google sign-in | Tokens `mock:<sub>:<email>` | Identity token checked against Apple / Google keys |

## Run the app

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:3000
```

Use `http://10.0.2.2:3000` on the Android emulator. Tests: `flutter test`.

The app uses mock Apple/Google sign-in and a mock Stripe card step until the
keys exist (see `lib/core/services.dart`). Swapping in `sign_in_with_apple`,
`google_sign_in` and `flutter_stripe` only touches that file and `main.dart`.

## Design assets

Fonts (Inter, Geist) are bundled. Illustrations and photos were exported
from Figma at 1x through the Figma connector, because direct asset downloads
from figma.com are blocked in the build environment. Replace the files in
`app/assets/images/` with 2x/3x exports before release; names are kept.
