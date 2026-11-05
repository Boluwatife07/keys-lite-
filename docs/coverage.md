# Requirement coverage

Status per sheet row group. "API test" and "App test" name the test file
that checks the behaviour; rows without a test are covered by the code path
noted.

## Milestone 1

| Rows | Behaviour | API | App | Status |
| --- | --- | --- | --- | --- |
| ONB-01 | Splash, then route | | `entry_screens.dart` | Done |
| ONB-02 | 4-slide intro, not shown again on the device | | `auth_test` | Done |
| ONB-03 | Resident / vendor choice (vendor = coming soon, Money lane) | | `auth_test` | Done |
| ONB-04 | No language screen in Phase 1 | | `auth_test` | Done (parked item hidden) |
| ONB-05 | Email entry, validation, consent links | `auth.test` | `auth_test` | Done |
| ONB-06 | Apple / Google, link to existing account, cancel | `auth.test` | mock in app | Done (real SDKs need keys) |
| ONB-07 | 6-digit code, 60 s expiry, resend, old code dies | `auth.test` | `auth_test` | Done |
| ONB-08 | Legal name + password rules | `auth.test` | `auth_test` | Done |
| ONB-09 | Login, wrong password, reactivation | `auth.test` | `auth_test` | Done |
| ONB-10 | Forgot password, signs out all sessions | `auth.test` | screens | Done |
| ONB-11 | Address lookup, structured address, not found | `onboarding.test` | `onboarding_test` | Done |
| ONB-12 | Community code: invalid, inside, outside, building -> parent | `onboarding.test` | `onboarding_test` | Done |
| ONB-13 | Matching: one, many, none, 500+ counts, linked streets | `onboarding.test` | `onboarding_test` | Done |
| ONB-14 | "Not my community" -> area type | | `onboarding_test` | Done |
| ONB-15 | Pioneer a street, race handled | `onboarding.test` | `onboarding_test` | Done |
| ONB-16 | House / building | `onboarding.test` | screens | Done |
| ONB-17 | Name / pick a building, duplicate names | `onboarding.test` | `onboarding_test` | Done |
| ONB-18 / 19 | Development name check (10 km), join existing, continue creation | `onboarding.test` | screens | Done |
| ONB-20 | Shape development, connected streets only, max 5, skip | `onboarding.test` | `onboarding_test` | Done |
| ONB-21 | "is live" / "Welcome to" | `onboarding.test` | screens | Done |
| ONB-22 | Photo required (15 MB, 1:1), bio 160, safety tick | `onboarding.test` | `onboarding_test` | Done |
| ONB-23 | Verify now or skip | `onboarding.test` | screens | Done |
| ONB-24 | Invite link, share sheet, copy toast, link page | `onboarding.test` | `onboarding_test` | Done |
| ONB-25 | Welcome prompt | `onboarding.test` | `verification_home_test` | Prompt done; "Post now" publishes once Feed lands (milestone 2) |
| ONB-26 | Resume at the first unfinished step | `onboarding.test` | `flow.dart` | Done |
| LRN-01 / 02 | 8-step tour, Back / Next / Skip, never again on any device | `onboarding.test` | `verification_home_test` | Done (copy changes need design sign-off) |
| AVW-01 | Methods by device | | `verification_home_test` | Done |
| AVW-02 | Card check, pass/fail only stored | `verification_media.test` | `verification_home_test` | Done (mock Stripe) |
| AVW-03 | Apple Pay / Google Pay, cancel | `verification_media.test` | screens | Done (mock wallet) |
| AVW-04 | Mismatch screen | `verification_media.test` | `verification_home_test` | Done |
| AVW-05 | Contest with document, encrypted, under review | `verification_media.test` | `verification_home_test` | Done |
| AVW-06 | Manual review outcome + email | `verification_media.test` (service) | | Service done; Admin Panel screen not in scope |
| AVW-07 | Explainer | | screens | Done |
| AVW-08 | Verify sheet, profile badge, Get verified | `auth.ts` guard | `verification_home_test` | Done |
| AVW-09 | Server guard for restricted actions | `requireVerified` | | Guard done; applied to each restricted endpoint as those features land |
| AVW-10 | No saved cards | schema check in `verification_media.test` | | Done (parked) |
| XFR-01 | Media limits, server re-check (type from bytes, ffprobe for video) | `verification_media.test` | `profile_screens.dart` | Done |
| XFR-02 | Share links, store fallback, preview tags, app links files | `onboarding.test` | `main.dart` | Done for community links; other item types as features land |
| XFR-03 | One report list, Other needs text | `verification_media.test` | | API done; report forms come with each feature |
| XFR-06 / 07 / 08 | English only, km, legal placeholders | | | Done |
| XFR-09 | Analytics events | | | Waiting for the event list (XFR-Q3) |

## Milestone 2

App tests: `app/test/feed_test.dart`, `app/test/profile_test.dart`. Checked end to end in the browser against the real API.

| Rows | Behaviour | API test | Status |
| --- | --- | --- | --- |
| PRF-01 / 02 / 19 | My profile, other profiles, My posts | `profile.test`, `feed.test` | Done |
| PRF-03 | Share profile, outsiders get not-available | `profile.test` | Done |
| PRF-04 | Mute 30 days, auto-ends, list, unmute | `profile.test` | Done |
| PRF-05 | Block two-way, unblock, list | `profile.test` | Done |
| PRF-06 | Report a resident | `profile.test` | Done |
| PRF-07 - 09 | Edit profile, photo (replace only), bio 160 | `profile.test` | Done |
| PRF-10 | Change email (password, code to new email, in use) | `profile.test` | Done |
| PRF-11 | Change home address with exit check, re-onboard | `profile.test` | Done |
| PRF-12 | Settings menu | | Done |
| PRF-13 | Blocked and muted lists | `profile.test` | Done |
| PRF-14 | Notification toggles, newsletter off | `profile.test` | Done (final list from Notifications task) |
| PRF-15 / 16 | Change password, create password for social accounts | `profile.test` | Done |
| PRF-17 | Log out, push token removed | `profile.test` | Done |
| PRF-18 | Deactivate, 7-day rule, exit check, 30-day deletion | `profile.test`, `auth.test` | Done |
| FED-01 | Feed, newest first, pages of 20, muted/blocked hidden | `feed.test`, `profile.test` | Done |
| FED-02 - 05 | Compose: 200 chars, one attachment type, 10 photos, video, document with title, link preview | `feed.test` | Done |
| FED-03 | @ tags, suggestions, notifications | `feed.test`, `profile.test` | Done |
| FED-08 / 10 | Full view, deleted and removed states | `feed.test` | Done |
| FED-11 | Likes and likes list | `feed.test` | Done |
| FED-12 - 14 | Comments, replies (one level), edit, delete placeholder | `feed.test` | Done |
| FED-15 / 17 | Copy, report, mute, block from posts and comments | `profile.test` (shared endpoints) | Done |
| FED-16 | Share post, non-members get not-available | `feed.test` | Done |
| FED-18 | Edit and delete own post | `feed.test` | Done |
| FED-19 | Notifications, never for own actions | `feed.test` | Done (push delivery with Firebase later) |
| POL-01 | Committee only (not champions) | `feed.test` | Done |
| POL-02 - 05 | Question, promise, 2-5 options, images all or none, multi, duration, publish | `feed.test` | Done |
| POL-06 / 07 / 08 | Vote once, final, verified only, results | `feed.test` | Done |
| POL-09 | Close, winner, notify | `feed.test` | Done |
| POL-10 - 13 | Comments/likes/share, delete, safety, unavailable | `feed.test` | Done (same as posts) |

### Known gaps in milestone 2

| Row | Gap | Plan |
| --- | --- | --- |
| FED-04.3 | Videos over 60 s are refused with a "Please trim your video" message instead of an in-app trim step | Add a native video trimmer package when building for devices |
| FED-07.2 | Video plays with play/pause/scrub; full-screen rotation not tuned | Device QA |
| PRF-02.2 | "Chat" opens a placeholder until Chat (milestone 4) | Milestone 4 |
| FED-19 | Notifications are stored and listed in the app; push sending needs Firebase keys | When keys exist |

## Milestone 3

API tests: `backend/test/board.test.ts`. App tests: `app/test/board_test.dart`. Checked in the browser against the real API.

| Rows | Behaviour | Status |
| --- | --- | --- |
| CBM-01 | Community tab: header, Hub, Proposals for committee only; hidden Phase 2 sections | Done |
| CBM-02 | No committee yet; verified only | Done |
| CBM-03 | Share community code and link | Done |
| CBM-04 | Create board: pledge, leadership question, role with About, answers (500) | Done |
| CBM-05 | Preset roles first come, first served; race refused cleanly | Done |
| CBM-06 | Apply for extra/champion seat; review; one application at a time; new seat protection; below 5 joins straight away | Done |
| CBM-07 | Board invite link and share | Done (opening the link inside the app comes with deep-link routing for all items) |
| CBM-08 | Welcome / Get started after joining | Success screen done; video guide waits for videos (none yet) |
| CBM-09 | Board: All / Members / Champions, Unoccupied seats, empty champions | Done |
| CBM-10 | Tiers explainer | Done |
| CBM-11 | Manage seats (Chair only), Tier 1 champions after 8 presets, occupied seats locked | Done |
| CBM-12 | Tier rise: Chair notified, banner | Done (milestone prompt waits for CBM-Q2) |
| CBM-13 / 14 | Exit with reason; Chair hands over to the Vice Chair, otherwise the seat is left empty | Done |
| CBM-15 / 16 | Reassign (swap) and remove proposals, 5+ only | Done |
| CBM-17 | Removed member told | Done (notification) |
| CBM-18 | Announcements with View reason / Apply / Reassign | Done |
| CBM-19 | Application and seat rules | Done |
| VOT-01 | Proposals list, filter, Closes today | Done |
| VOT-02 - 04 | Join, reassign, remove details, Yes/No, reasons, results and voters | Done |
| VOT-05 | Rules: 5+, auto Yes, >50% early close, 7 days, ties pass, committee only, seat protection, no longer applicable | Done |
| VOT-06 | Notifications: created, 24-hour reminder, result, board changes | Done |
