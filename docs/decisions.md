# Decisions taken during the build

Answers from Dorcas (5 Nov 2026) and defaults chosen where the sheet says
"Needs check". Each default is isolated in code so it is cheap to change.

## Answered by Dorcas

| Question | Answer | Where it lives |
| --- | --- | --- |
| Stack | Flutter app; backend left to engineering (Node + TypeScript + PostgreSQL chosen) | `app/`, `backend/` |
| Address lookup provider | Google Places | `backend/src/services/places.ts` |
| Outside services before keys exist | Mock them | `MOCK_*` settings |
| CBM-Q1: board below 5 members | Applicants join automatically, no vote | Committee milestone |
| POL-Q1: change or undo a poll vote | Not allowed. Votes are final | Polls milestone |
| VOT-Q1: champion offer after a declined application | No such path | Voting milestone |
| XFR-Q1: report reasons | One shared list (written below) | `backend/src/lib/rules.ts` |
| AVW-Q1: Stripe pass rule | Engineering's choice: postcode **and** first address line must pass | `backend/src/services/addressCheck.ts` |
| Admin Panel manual review | Not in this build. The resident can still submit a document and sees "under review"; the decision function exists for the Admin Panel to call | `backend/src/modules/verification/service.ts` |
| Legal documents | Placeholder links | `TERMS_URL`, `PRIVACY_URL`, `SAFETY_URL` |

## Defaults chosen (please confirm)

| Topic | Default | Why |
| --- | --- | --- |
| ONB-Q1: resident counts on cards | Only for 500+ residents (PRD) | Sheet row ONB-13.4 |
| AVW-Q4: verification document size | 10 MB, PDF/JPG/PNG (design copy) | Matches the screen text |
| AVW-Q3: re-upload after rejection | Rejected resident is back to unverified and can try the card again or contest again | No rejection screen is designed |
| Verification attempts | 5 card/wallet checks per 24 hours | Engineering baseline in the sheet |
| Billing address on the card check | Always the Keys home address, sent by the server to Stripe | Keys never reads an address back from Stripe (AVW-02.5) |
| Email code | 6 digits, 60 s, max 5 wrong tries, 6 codes per email per hour | Sheet + baseline |
| Login lockout | 5 wrong passwords -> 15 minutes | Baseline |
| Password reset | Signs out every session | ONB-10.4 |
| Social account with no password | Confirms legal name, then normal onboarding | ONB-06.1 "continues to account setup" |
| Development streets | Up to 5 connected streets *in addition to* your own | ONB-20.2 |
| "Directly connected" streets (Google) | Reverse-geocode a ring of points around the street | Google has no road-graph call. Needs check: OS / OSM road data may be more accurate |
| Building match by code | Same street and same house/building number -> join the building; same street, other number -> parent community (ONB-12.5) | Buildings are named, not addressed, so the number is the only reliable key |
| Copy "Pls" (ONB-07.4) | "Please" | Sheet note |
| Learning steps 2, 3, 4 | Copy drops News, scheduled posts, projects/resources/budgets | LRN-02 notes; needs design sign-off |
| Shape development copy | Drops "and the committee can add them later" | Design vs PRD ONB-D4 |
| Invite copy "futher" | "further" | Typo in design |
| Language picker on the choice screen | Hidden; English (UK) only | ONB-04.1 |

## Shared report reasons (XFR-03.1)

1. Spam or misleading
2. Harassment or bullying
3. Hate speech or discrimination
4. Violence or threats
5. Nudity or sexual content
6. Scams or fraud
7. False information
8. Impersonation
9. Sharing private information
10. Other (text required)
