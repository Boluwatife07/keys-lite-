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
| 2 | Profile and settings, Feed, Polls | Done |
| 3 | Committee board, Voting | Done |
| 4 | Updates, Update chat, Chat | |
| 5 | Free events, Free clubs, Calendar | |

Requirement-by-requirement coverage: [`docs/coverage.md`](docs/coverage.md).

## Run it on your computer

You need: [Node.js 22](https://nodejs.org), [PostgreSQL 14+](https://www.postgresql.org/download/),
[Flutter 3.47+](https://docs.flutter.dev/get-started/install) (run `flutter upgrade` if yours is older) and Chrome. `ffprobe` (part of
[ffmpeg](https://ffmpeg.org)) is only needed for video uploads.

**1. Get the code**

```bash
git clone https://github.com/Boluwatife07/keys-lite-.git
cd keys-lite-
git checkout claude/hopeful-mccarthy-vdo9v6
```

**2. Start the API** (terminal 1)

```bash
createdb keys
cd backend
npm install
cp .env.example .env
npm run seed
npm run dev
```

`.env.example` expects Postgres on `localhost:5432` with your own user; edit `DATABASE_URL`
in `.env` if yours is different. Every outside service (email, address lookup, card check,
Apple/Google) runs as a mock, so no keys are needed. The API runs on http://localhost:3000.

**3. Start the app** (terminal 2)

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

On a phone simulator use `flutter run` instead (Android emulator: `API_BASE_URL=http://10.0.2.2:3000`).

**4. Log in**

`npm run seed` creates a demo street, Maple Road. The password for every account is `Keys2026!`.

| Email | Who |
| --- | --- |
| amy@keys.test | Chair, verified: proposals, voting, manage seats, create polls |
| ashley@keys.test | Vice Chair (also eric, brianna, ajani, tobias, nadine, omari) |
| ben@keys.test | Unverified resident: try voting or joining the board |
| paula@keys.test | Has applied for a Champion seat |

To try sign-up, use any new email: the 6-digit code is printed in the API terminal.
Mock addresses: `5 Cedar Close` (no community yet), `4 Elm Street` (development with connected
streets), `2 Maple Road` (joins the demo street). Card check: `4242 4242 4242 4242` passes,
`4000 0000 0000 0002` fails, any future expiry and CVV.

### Tests

```bash
cd backend && npm test      # needs TEST_DATABASE_URL, default postgres://keys@localhost:5433/keys_test
cd app && flutter test
```

### Mock mode

| Service | Mock behaviour | Real service |
| --- | --- | --- |
| Email | Codes print in the API terminal and are saved in `email_outbox` | Resend |
| Address lookup | A small fake London neighbourhood plus one street in Brighton | Google Places (New) |
| Card address check | App: cards ending `0002` fail, others pass | Stripe SetupIntent, `address_line1_check` and `address_postal_code_check` must both pass |
| Apple / Google sign-in | Signs in a demo account | Identity token checked against Apple / Google keys |

The app's mocks for Apple/Google sign-in and the Stripe card step live in
`app/lib/core/services.dart`; swapping in `sign_in_with_apple`, `google_sign_in` and
`flutter_stripe` only touches that file and `main.dart`.

## Design assets

Fonts (Inter, Geist) are bundled. Illustrations and photos were exported
from Figma at 1x through the Figma connector, because direct asset downloads
from figma.com are blocked in the build environment. Replace the files in
`app/assets/images/` with 2x/3x exports before release; names are kept.
