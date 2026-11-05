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

## Milestone 2 (backend done, screens next)

| Rows | Behaviour | API test | Status |
| --- | --- | --- | --- |
| PRF-01 / 02 / 19 | My profile, other profiles, My posts | `profile.test`, `feed.test` | API done |
| PRF-03 | Share profile, outsiders get not-available | `profile.test` | API done |
| PRF-04 | Mute 30 days, auto-ends, list, unmute | `profile.test` | API done |
| PRF-05 | Block two-way, unblock, list | `profile.test` | API done |
| PRF-06 | Report a resident | `profile.test` | API done |
| PRF-07 - 09 | Edit profile, photo (replace only), bio 160 | `profile.test` | API done |
| PRF-10 | Change email (password, code to new email, in use) | `profile.test` | API done |
| PRF-11 | Change home address with exit check, re-onboard | `profile.test` | API done |
| PRF-12 | Settings menu | | App only |
| PRF-13 | Blocked and muted lists | `profile.test` | API done |
| PRF-14 | Notification toggles, newsletter off | `profile.test` | API done (final list from Notifications task) |
| PRF-15 / 16 | Change password, create password for social accounts | `profile.test` | API done |
| PRF-17 | Log out, push token removed | `profile.test` | API done |
| PRF-18 | Deactivate, 7-day rule, exit check, 30-day deletion | `profile.test`, `auth.test` | API done |
| FED-01 | Feed, newest first, pages of 20, muted/blocked hidden | `feed.test`, `profile.test` | API done |
| FED-02 - 05 | Compose: 200 chars, one attachment type, 10 photos, video, document with title, link preview | `feed.test` | API done |
| FED-03 | @ tags, suggestions, notifications | `feed.test`, `profile.test` | API done |
| FED-08 / 10 | Full view, deleted and removed states | `feed.test` | API done |
| FED-11 | Likes and likes list | `feed.test` | API done |
| FED-12 - 14 | Comments, replies (one level), edit, delete placeholder | `feed.test` | API done |
| FED-15 / 17 | Copy, report, mute, block from posts and comments | `profile.test` (shared endpoints) | API done |
| FED-16 | Share post, non-members get not-available | `feed.test` | API done |
| FED-18 | Edit and delete own post | `feed.test` | API done |
| FED-19 | Notifications, never for own actions | `feed.test` | API done (push delivery with Firebase later) |
| POL-01 | Committee only (not champions) | `feed.test` | API done |
| POL-02 - 05 | Question, promise, 2-5 options, images all or none, multi, duration, publish | `feed.test` | API done |
| POL-06 / 07 / 08 | Vote once, final, verified only, results | `feed.test` | API done |
| POL-09 | Close, winner, notify | `feed.test` | API done |
| POL-10 - 13 | Comments/likes/share, delete, safety, unavailable | `feed.test` | API done (same as posts) |
