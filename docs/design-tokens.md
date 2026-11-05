# Design tokens: light and dark

The Resident APP Figma files only have light screens, but the variables they
use come from the **Keys - Design System V2** library, whose *Semantic Colors*
collection has a **Light Mode** and a **Dark Mode**. The dark palette in
`app/lib/theme/tokens.dart` uses those Dark Mode values. They were read from
the library with the Figma plugin API on 5 Nov 2026.

| App token (`KColors`) | Design system variable | Light | Dark |
| --- | --- | --- | --- |
| textPrimary | text/default | #171717 | #F3F3F3 |
| textSecondary | Misc/neutral 600 | #5E5E5E | #A6A6A6 |
| textTertiary | (Grey/400 area) | #8F8F8F | #868686 |
| textInverse | text/inverse | #FFFFFF | #171717 (design system: #000000) |
| textLink | text/link, secondary/blue/default | #329CFF | #54ACFF |
| iconDefault | icon/default | #171717 | #E8E8E8 |
| iconMuted | Grey/400 (list carets) | #868686 | #868686 |
| iconDisabled | icon/disabled | #A6A6A6 | #5E5E5E |
| borderDefault | border/default | #E8E8E8 | #4B4B4B |
| borderSubtle | border/subtle | #F3F3F3 | #282828 |
| borderStrong | border/inverse | #282828 | #E8E8E8 |
| surfaceDefault | surface/default | #FFFFFF | #171717 |
| surfaceSubtle | surface/subtle | #F3F3F3 | #282828 |
| surfaceMuted | surface/medium | #E8E8E8 | #4B4B4B |
| surfaceInverted | surface/inverted | #171717 | #F3F3F3 |
| surfaceElevated | (sheets, dialogs; app file's surface-page) | #FFFFFF | #282828 |
| brand | brand/default | #FFD12A | #FFD12A |
| brandSubtle | brand/subtle | #FFF9EA | #332800 |
| brandMuted | brand/muted | #FFF4CC | #7F6400 |
| success | status/success/default | #21AE48 | #46BB66 |
| successSubtle | status/success/subtle | #E6F6EA | #0B3A18 |
| error | status/error | #D92D20 | #E96078 |
| errorSubtle | status/error/subtle | #FDECEA | #4A0612 |
| warningSubtle | status/warning/subtle | #FFEDB0 | #4A3200 |
| selected | secondary/teal/default | #1C8C86 | #2A9595 |
| selectedSubtle | secondary/teal/subtle | #DDF2F0 | #001A1A |
| dashed | surface/strong | #DDDDDD | #5E5E5E |

Kept the same in both modes, as the design system does:
- the brand yellow, and black content on it (`staticBlack`);
- white on photos, video and the dark welcome carousel (`staticWhite`);
- overlays.

Poll colours follow secondary/purple and secondary/green, and club category
tags follow secondary/purple.

## How switching works

`KTheme` (`app/lib/theme/theme_controller.dart`):
- saves the choice on the device (`light`, `dark` or `system`);
- sets `KColors.palette`;
- follows the phone's setting when "Use device default settings" is on.

When the palette changes, `KeysApp` rebuilds every widget, so the current
screen and the navigation history are kept.
