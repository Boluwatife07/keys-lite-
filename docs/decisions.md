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
| ONB-Q1: resident counts on onboarding cards | Shown only above 500 residents (501+), on matches, similar developments and the building list | `countsVisible` in `backend/src/modules/onboarding/communities.ts` |
| PRF-Q1: dark mode | Phase 1 (Dorcas). Settings > Display has Light mode, Dark mode and Use device default settings; exactly one is on, Light is the default, the choice is saved on the device. Dark colours are the design system's own Dark Mode values (see `docs/design-tokens.md`) | `app/lib/theme/` |
| Icons | Phosphor (Regular, Fill, Bold) as named in Figma; fonts bundled because `phosphor_flutter` no longer builds | `app/lib/theme/phosphor.dart` |
| Legal documents | Placeholder links | `TERMS_URL`, `PRIVACY_URL`, `SAFETY_URL` |

## Defaults chosen (please confirm)

| Topic | Default | Why |
| --- | --- | --- |
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

## Milestone 2 defaults (please confirm)

| Topic | Default | Why |
| --- | --- | --- |
| Poll option limit | 40 characters (sheet). Design counter shows /50 | Sheet row POL-03.1 |
| POL-D3: poll promise limit | 200 characters | Filled design state shows 116/200; the 0/50 counter looks out of date |
| POL-Q3: poll notifications | None on creation (same as Feed posts); creator and voters are told when it closes | Keeps notification volume low |
| Poll results before voting | Hidden until you vote, the poll closes, or you created it | Avoids results swaying votes |
| Multi-select results | Each option shows its share of voters (POL-07.2) | Sheet row |
| Ties | Every option with the top count is marked as winning | Not specified |
| Editing a post | Text and tags only; attachments stay | Not specified beyond "Edit post" |
| Comment length | 1,000 characters | Not specified |
| Feed document downloads | Open to unverified residents too | AVW-09 restricts "community or update documents"; Feed files are posts, not Resources |
| Mute | Hides the muted person's posts from your Feed and stops their notifications; their comments still show | PRF-04.3 names posts and notifications only |
| Block | Two-way: posts, comments, likes lists, profile, @ suggestions and notifications. The blocker still sees the profile with "Unblock" | PRF-05.2 / PRF-05.3 |
| Profile visibility | Only residents of the same community; others get "not available" | PRF-03.3 |
| Change password | Signs out your other devices | Baseline |
| Create password (social accounts) | Needs an email code | PRF-16.2 mentions a code |
| Change home address | A committee seat is a warning and is revoked; hosting an event with tickets issued or being a club President blocks | PRF-11.1, PRF-11.5 (member exit rules file not shared with me) |
| Deactivate | Committee seat, event with tickets or club presidency blocks it; social accounts must add a password first | PRF-18.5 |
| Notification toggles | Likes, comments, mentions, polls, updates, committee, chat, events, clubs; newsletter email off by default | Final list waits for the Notifications task |

## Milestone 3 defaults (please confirm)

| Topic | Default | Why |
| --- | --- | --- |
| CBM-Q1: applications below 5 members | Join straight away, no vote (Dorcas) | Decided 5 Nov |
| VOT-Q1: champion offer after a declined application | None (Dorcas) | Decided 5 Nov |
| Chair leaves with no Vice Chair | The Chair seat is left empty and filled the normal way (any verified resident can take it, first come first served) | Dorcas, 5 Nov 2026 |
| Who is an eligible voter | Committee members (preset and extra seats). Champions never vote. The subject of a removal cannot vote | VOT-04.3, VOT-05.5 |
| Early close | More than half of eligible voters cast the same vote | VOT-05.3 |
| At 7 days | Only cast votes count; ties pass, including 0-0 | VOT-05.4 |
| Votes | Final once cast | Baseline |
| Reason for No | Required on reassign and remove; optional on join | VOT-03.2 |
| Reassign | Committee members only (not champions); into a vacant seat or swap with the holder | CBM-15, CBM-16.1 |
| Removing yourself | Not a proposal; use Exit committee | Confirmed by Dorcas, 5 Nov 2026 |
| One open proposal per member and type | A second remove/reassign for the same person is refused while one is open | Avoids duplicate votes |
| Tier drop | Nobody is removed; seats above the new allowance cannot be activated or applied for | CBM-12.4 |
| Moving home or deactivating | Seat ends (with a Board exit card), applications are cancelled, proposals by or about the person become "No longer applicable" | CBM-19.2, VOT-05.7 |
| Role descriptions ("About the role") | Short Phase 1 texts without wallet or project powers | Confirmed by Dorcas, 5 Nov 2026 |
| CBM-Q2: milestone prompt ("[N] members strong") | Fires when the community reaches a new tier: 100, 400 and 700 residents (Dorcas). Each milestone fires once, also with no committee board. Shown on the Community tab to residents who were members when it was reached, for 30 days or until closed or "View new residents" is tapped. "New residents" are those who joined since the previous milestone. Copy says "has welcomed [N] new residents" (exact count, so "over" is dropped). No push notification | `backend/src/modules/board/milestones.ts` |
| CBM-08.2: "Getting started" video guide | Not built; no videos yet. New members see the success screen | Dorcas, 5 Nov 2026 |
| Board announcement copy | Uses "their" where the design says "his" | Neutral copy |

## Milestone 4 defaults (please confirm)

| Topic | Default | Why |
| --- | --- | --- |
| Who sees sub-community updates | Residents of the chosen streets and buildings; committee members see every update so they can manage them | UPD-01.4 |
| Images per update (UPD-D2) | Up to 10 | No maximum in the design or PRD |
| Audience picker search (UPD-D3) | Included: search streets and buildings by name | Shown in the design |
| Pins (UPD-D4) | Each resident pins up to 3 updates for themselves | UPD-08 |
| "Set this as my default audience" | Not built; each update starts at All residents | No rule for it in the PRD |
| "Schedule this update" | Not built | Scheduling is a later-phase item |
| Unread updates | Unread until opened, and again when someone else adds an additional update. Authors have read their own | UPD-01.2 tint and dot |
| Additional update @tags | Committee members only | UPD-06.3 |
| Chat tabs | All, Primary, Groups, Clubs, Events, Services, Volunteering. Services and Volunteering stay empty until those features exist | CHT-01.2 |
| Chat notifications | Delivered live in the app and by push; not added to the in-app notification list | Avoids a duplicate list |
| Blocking in a direct chat | The person who blocked cannot send until they unblock ("You blocked this user. Tap to unblock."). The blocked person's messages show Sent and are never delivered | CHT-05.5 |
| Leaving the board or the community | The person also leaves the community's update chats | UCH-04.2 |
| Voice notes | Up to 10 minutes and 25 MB; tap the mic to record, tap send to stop and send | CHT-07 |
| Photos per message | Up to 10, or one video (60 s, 100 MB), or one document (25 MB), sent separately | Same limits as posts |
| Forwarding | Up to 5 chats, with an optional note | CHT-08.4 |
| Group system messages | Use the person's name, also for your own actions ("Amy Duncan created this group") | One text for everyone |

## Milestone 5 defaults (please confirm)

| Topic | Default | Why |
| --- | --- | --- |
| EVT-Q1: external co-hosts | Included; they count towards the 5 co-host limit and show as "External" | In the design; one limit is simpler |
| CLB-Q1: club description length | Kept at 300; the 8 templates are written to fit | PRD limit |
| What launching an event needs | Title, description, at least one photo or video, date and time, a place (physical) or platform and link (online), and 1 to 3 tags | Fields marked required in the design |
| Event length | Single-day for residential, administrative and club events; multi-day is vendor only | EVT-07.2 |
| Who can take a ticket | Verified residents, one at a time; the host cannot take one; seats are numbered from 001 | EVT-19 |
| Capacity after launch | Can change, but not below the tickets already taken | Keeps issued tickets valid |
| Draft reminder | "Still planning [Event]?" after a draft is untouched for 3 days | EVT-12.5 timing not set |
| Rating prompt | From the day after the event (UK time); closing it without rating dismisses it for good | EVT-24.2 |
| Event day for scanning | The event's start date in UK time | EVT-23.5 |
| Volunteers | Leaving or being removed from the planning chat ends volunteering; removed volunteers cannot volunteer again | EVT-17.3, EVT-22.4 |
| Stepping down from the board | Blocked while hosting a live event with tickets taken | EVT-27.1 |
| Club members limit | Required, minimum 10, never below the current member count | CLB-03.1, CLB-09.1 |
| Club categories | Lifestyle, Sports, Music, Food & Drink, Creative, Gaming, Pets, Wellness, Learning, Others | Design shows part of the list |
| Club creation steps | Form, then "Add members" (can be skipped), then "Club created!" | CLB-03.4, CLB-03.5 |
| Ownership transfer | The old President leaves the club once the offer is accepted; their club events pass to the new President; a "New President" announcement is posted for everyone | CLB-11, design |
| Club chat | Mirrors club membership; it cannot be left or joined on its own | CLB-15.1 |
| Club announcement delete | The author or the President | CLB-13.4 |
| Home calendar preview | When nothing is coming up in 4 weeks, only the "Upcoming / Calendar →" row stays | Keeps the calendar reachable |
| Calendar items | Updates on the day they were posted (gone once resolved or deleted); events for ticket holders, host, co-hosts and volunteers | CAL-04 |
| Not built | Paid tickets and clubs, vendor events, donations, sub-community event audience, attendee spreadsheet, scheduled announcements, Services calendar items | Money lane or later phase |

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
