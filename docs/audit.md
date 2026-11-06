# Design and logic audit

Each feature is checked screen by screen against the Figma frames (light and
dark) and against its acceptance rows. The app screens are rendered by the
catalogue test (`app/test/catalog`, run with
`flutter test --update-goldens test/catalog`) at the iPhone 15 frame used in
Figma (393 x 852).

Status: **Onboarding, Address verification, Learning and Profile/Settings
done.** Next: Feed, Polls, Committee board, Voting, Updates, Update chat,
Chat, Events, Clubs, Calendar.

## Onboarding

### Shared components (fixed once, used everywhere)

| Item | Before | Figma / now |
| --- | --- | --- |
| KEYS logo | PNG, black only (invisible in dark mode) | Vector from Figma, follows the text colour |
| Page header | 44 high, 30pt caret, 8 inset | 48 high, 26pt caret, 16 inset |
| Onboarding progress | 6pt, orange to yellow on border grey | 8pt on surface/subtle, orange 500 > orange 200 > brand subtle > brand |
| Disabled primary button | 25% black | surface/subtle with text/disabled |
| Heading/Small | Geist 22/28 | Geist 24/32, -0.5 |
| Overline | Inter 11 | Inter Medium 10/16, 1pt tracking |
| Text field | 50 high with a hidden border, tertiary placeholder | 48 high, text/placeholder (#727272), optional leading icon and "(Optional)" note |
| Field error | 1pt border, icon + 13pt text | 2pt red border on white, plain 12pt red hint 10 below |
| Password rules | 16pt icons, 13pt text | 11pt ring / tick / cross, 12pt (14pt on reset) |
| Code boxes | 46 x 52, white, outlined | 48 square, radius 12, surface/subtle |
| Choice cards | radius 12, 110 image | radius 16, padding 16, 120 image, equal heights |
| Button stack gap | 12 | 10 |
| Bottom action | 16 above the home indicator | sits on the home indicator (16 margin when there is none) |

### Screens

| Screen | Fixes |
| --- | --- |
| Choose how to use Keys | Space kept for the language picker (not in Phase 1), centred block, 48pt logo, 16pt cards, curly apostrophes |
| Intro carousel | Full-height photos with the Figma fade, 3pt bars, 12pt Skip, 20pt text inset; Next stays white in dark mode |
| Email | Back caret, "Email" label and placeholder, inset "or" divider, consent line pinned to the bottom |
| Verify email / reset code | Figma spacing; reset adds "Reset code" label and "to reset your password" |
| Create account | Figma copy, placeholders, "Create password", progress 5% |
| Log in | 12/36 spacing, underlined SemiBold "Forgot password?" under the field |
| Forgot / new password / reset done | Figma copy and spacing; green double-tick mark; reset button inline |
| Home address | Back (signs out to the email step), search and key icons, floating suggestion card over the code field, progress 20%; Continue waits for a pick while suggestions are open |
| Community matching | Geist Mono code pill, 72pt badge, 24pt name, Figma counts, progress 50% |
| Pick your community | Teal-label cards with icon disc and 2pt teal selected outline; button reads "Join community" |
| Area not on Keys / area kind / confirm street | Centred hero layouts at Figma sizes |
| Name your development | Tree icon, placeholder, no counter |
| Similar developments | Orange disc cards, "committee members", orange distance tag, outlined "Continue with creation" |
| Join existing development | Grey summary card with ruled rows and bullet list, bold street in the copy, "Join community" |
| Shape your development | Teal name tag, street map with house pins, checkbox list (your street locked), Skip in the header, "Add streets"; max 5 message under the list |
| Home type / pick building / name building | Figma cards, teal building rows, yellow community box, buildings icon |
| Street / building live, welcome | 36/48 titles on two lines, 270 image, 52 top inset |
| Profile setup | 120 avatar with yellow camera button, size hint, 4-line bio, safety tick above Continue |
| Verify prompt | Link under the copy, centred illustration (transparent for dark mode), grey "Skip for now" |
| Invite | Close and Skip in the header, 36pt title, dark "Tap to share" card (long press copies) |

### Logic checked

- ONB-11.3 typed address without a pick is refused; ONB-12.2 invalid code under the code field.
- ONB-13.4 resident and committee counts only above 500 residents (server leaves them out).
- ONB-13.2 join inactive until a community is picked.
- ONB-14.2 area kind Proceed inactive until a type is chosen.
- ONB-19 similar development names; ONB-20.1 / 20.2 only connected streets, max 5, Skip creates with none.
- ONB-21 live vs welcome copy (the server's `live` / `welcome`).
- ONB-22 photo and safety tick required; ONB-24 share and copy.

### Kept on purpose (design differs)

- **Committee can add streets later**: the Figma copy says so, but that is Phase 2
  (decision ONB-D4), so the copy ends at "You can skip this step."
- **No back button** after a community is joined (home type, live screens,
  profile, verify): the join cannot be undone from there.
- **Progress values** follow the frames where they agree (address 20%,
  matching to development 50%); the profile frame shows a full bar, which
  would go backwards before verify, so the app keeps 75% / 85% / 95%.
- **Building live screen**: the Figma frame uses the web top bar with the
  logo; the app keeps the onboarding header like the street version.
- **Map**: with a Google Maps key on the server the map is a real static map
  (`/maps/static`); without one the app draws a simple street sketch with
  the same pins.
- Text in the tests wraps slightly wider than Figma (Inter version); sizes,
  spacing and colours match.

## Address verification

| Screen | Before | Figma / now |
| --- | --- | --- |
| Choose a method | Full page with radio rows | Bottom sheet over the page that opened it: grabber, "Verify address" title and close, grey rows with radio, label and brand mark (card, Apple Pay, G Pay) |
| Bank card | Separate page | Opens inline under "Verify with Bank card": card number with card icon, expiry and CVV side by side, read-only billing address box (your Keys home address, one part per line), note |
| Successful | Green disc, "Continue" | Green double-tick ring under the "Verify your home address." heading, "Proceed" |
| Couldn't verify | Full page, "Try again" first | Sheet with the red cross ring, grey info card (method with wallet mark, house icon + address), "Contest this decision" first, "Try again" second, footnote |
| Upload a supporting document | Plain list, grey upload box | "Contest verification" label, white card of accepted documents with teal ticks, dashed upload area with cloud icon, lock note under the button |
| Under review | Card with ref and estimate | Full-height card over the page: clock disc, timeline (submitted, in review with estimate, outcome), submitted PDF row with reference |
| How does verification protect me? | Text only | Hero illustration and three illustrated sections from Figma |

Logic checked: AVW-01.2 Verify inactive until a method is chosen (and, for a
card, until number, expiry and CVV are filled); AVW-02 Luhn, expiry and CVV
checks; AVW-03.2 a cancelled wallet sheet leaves you on the sheet; AVW-04
mismatch shows the method and the Keys address; AVW-05.4 under review opens
the review screen; AVW-08.1 the verify sheet on restricted actions.

Kept on purpose: the wallet row shows Apple Pay on iPhone and Google Pay on
Android only (Figma shows both; each only works on its own platform). The CVV
is shown as typed, as in Figma. The explainer illustrations are 1x exports
from Figma until 3x files are available.

## Learning tour

| Item | Before | Figma / now |
| --- | --- | --- |
| Overlay | 60% black, plain cut-out | 50% #171717 with a 2pt yellow ring round the highlighted area |
| Card | Material buttons, Skip at the top | Radius 12, soft shadow, "Step n of 8" + close X, 18pt title, 14pt copy, Skip bottom-left, Back (outlined) and Next on the right; widths per step from Figma |
| Sample cards | None | Feed post, committee board, club, service and event samples exported from the Figma frames |
| Bottom bar | Material bar with a yellow pill | Figma "Floating Nav bar": top rule, 28pt ic28 icons (filled when active), SemiBold 12 labels, 20pt top inset; each tab is one labelled button for screen readers |

Logic checked: LRN-01 Next / Back / Skip / close, completion and skip are
recorded; LRN-02 later-phase items (News, scheduled posts, projects, budgets)
stay out of the copy and samples, so step 2 keeps "Feed and Updates" and step
4 shows the committee board only (the Figma Budget card is later phase).

Kept on purpose: the last step's button reads "Finish" (Figma repeats
"Next"); step 1 highlights the yellow compose button rather than the empty
state's "Create post"; Services has no filled icon in Figma, so it stays
outlined when active.

## Profile and settings

| Screen | Fixes |
| --- | --- |
| My profile | Page header with 28pt gear and share icons; grey page with white sections; 80 avatar, SemiBold 20 name, 36pt Edit profile / Get verified buttons; "My Activities" in Geist 16 with the 34pt chip |
| Other resident | Same profile block; 16/24 bio; 48pt Chat; 72pt action rows with 28pt icons (share, mute, block, report) |
| Edit profile | Page header, 120 avatar with 36pt pencil, 72pt rows (16/24 label, 14/20 value) |
| Bio sheet | Grabber, 18pt title, copy and close X, labelled field with counter, rule, Save |
| Change email | Password step and new-email step copy, placeholders and underlined current email from Figma |
| Settings / Display | Already matched |
| Account | Titled "Account", key and heart-break icons, Log out pinned under an 8pt grey band |
| Notification | Grey page with white "In-app notification" and "Email notification" sections, Geist 20 titles, ruled rows, Figma switches |
| Privacy & Safety | Text-only rows |
| Mute | Centred modal with Cancel and a red "Yes, mute" |
| Block (and every confirmation sheet) | Figma action sheet: picture (block), title, copy, yellow "won't be notified" note, rule, stacked action and Cancel; red action when destructive |

Kept on purpose: Settings shows only Phase 1 rows (address book, payment
methods, security and language are later phase); notification rows are the
Phase 1 notification types (the Figma rows are later-phase features);
"Edit profile" moved off the Account page as in Figma but stays on the
profile; Edit profile keeps Home address and Verify rows (PRF-11, AVW-08);
the bio limit stays 160 characters (ONB-22), Figma shows 200; My Activities
shows "My post" only (other tabs are later phase).

## Home feed (part 1: home, post card, compose, comments)

| Item | Fixes |
| --- | --- |
| Home header | 36 avatar; 36pt round buttons with 28pt ChatCircleText and BellSimple; red count badge |
| Compose button | 52pt yellow disc with the two Figma shadows (no outline) |
| Empty feed | 137pt grey disc with the mailbox, 18pt title, 14pt copy, small outlined "Create post", on white |
| Post card | 16 top inset, 36 avatar, 12pt time, 36pt options; 16/24 text; stats row with Medium counts; 48pt action row under a rule with Heart, ChatCircleDots and ShareFat; posts 4pt apart on grey |
| Compose | X, avatar, "Everyone ⌄", small Post button; 20/28 text; 56pt typing bar with 36pt buttons and 24pt icons |
| Comments sheet | Inter 18 title |

Kept on purpose: no News tab (later phase); no schedule clock in compose
(scheduled posts are later phase); the compose bar keeps a separate video
button and has no marketplace button (later phase); the character counter
stays (FED-02).

## Home feed (part 2: post options, report, share, likes)

| Item | Fixes |
| --- | --- |
| Report form (shared by posts, comments, people, clubs, events, chats) | Inter 18 title with copy and close X, ruled 52pt radio rows with the Figma radio, Submit under a rule |
| Share | Figma share sheet: title over a row of targets (Copy link, Share via) |
| Likes | "Likes" page header, yellow count band, ruled 60pt rows with committee badge, role and red heart marker |
| Post options | Already matched |

Kept on purpose: the share row offers Copy link and the phone's share sheet
only (Message, Facebook and WhatsApp are reached through the phone's sheet);
reports keep the "Other" reason with a text box (XFR-03).

## Home feed (part 3: post detail, photo viewer)

| Item | Fixes |
| --- | --- |
| Post detail | Back-only header, post edge to edge, small SemiBold "Comments" label, Figma empty comments with "Write a comment" |
| Photo viewer | Translucent top bar with back caret, author photo, name and badge; caption in a translucent bottom band |

Kept on purpose: the photo viewer has no Like/Comment/Share row (those stay
on the post); photos are shown whole (not cropped) so they can be zoomed;
the post detail has no second options button in the header (the post's own
options button is right below it).
