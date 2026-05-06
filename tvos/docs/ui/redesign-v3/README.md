# ChiakiTV — v3 Redesign

Each screen has its own capture and its own rationale doc. Margins,
alignment, typography, and component choices are all justified against
published UX/UI research (citations live in each rationale doc).

## Frame index

| # | Frame | Capture | Design rationale |
|---|---|---|---|
| 01 | Home (host visible) | [`01-home.png`](./01-home.png) | [`RATIONALE-01-home.md`](./RATIONALE-01-home.md) |
| 04 | Settings — Stream | [`04-settings-stream.png`](./04-settings-stream.png) | [`RATIONALE-04-settings-stream.md`](./RATIONALE-04-settings-stream.md) |
| 05 | Settings — Network | [`05-settings-network.png`](./05-settings-network.png) | [`RATIONALE-05-settings-network.md`](./RATIONALE-05-settings-network.md) |
| 06 | Settings — Controller | [`06-settings-controller.png`](./06-settings-controller.png) | [`RATIONALE-06-settings-controller.md`](./RATIONALE-06-settings-controller.md) |
| 07 | Settings — Consoles | [`07-settings-consoles.png`](./07-settings-consoles.png) | [`RATIONALE-07-settings-consoles.md`](./RATIONALE-07-settings-consoles.md) |
| 08 | Settings — App | [`08-settings-app.png`](./08-settings-app.png) | [`RATIONALE-08-settings-app.md`](./RATIONALE-08-settings-app.md) |
| 09 | Sheet — Manual Host | [`09-manual-host.png`](./09-manual-host.png) | [`RATIONALE-09-manual-host.md`](./RATIONALE-09-manual-host.md) |
| 10 | Sheet — Console PIN | [`10-console-pin.png`](./10-console-pin.png) | [`RATIONALE-10-console-pin.md`](./RATIONALE-10-console-pin.md) |
| 11 | Sheet — Register | [`11-register.png`](./11-register.png) | [`RATIONALE-11-register.md`](./RATIONALE-11-register.md) |
| 12 | Confirm dialog | [`12-confirm.png`](./12-confirm.png) | [`RATIONALE-12-confirm.md`](./RATIONALE-12-confirm.md) |

## Shared design system (cross-cuts every rationale)

### 8pt grid spacing tokens

Live in [`Theme.swift`](../../../tvos/ChiakiTV/Theme/Theme.swift) under
`// MARK: - v3 Design Tokens (8pt grid)`:

```
space1 =   4   space5 = 24
space2 =   8   space6 = 32
space3 =  12   space7 = 48
space4 =  16   space8 = 80
```

Every padding, gap, and frame in v3 source code uses one of these
tokens — there are no raw pixel values at call sites. The grid follows
[Spec.fm's 8pt grid](https://spec.fm/specifics/8-pt-grid) and
[Apple HIG's tvOS safe-area inset](https://developer.apple.com/design/human-interface-guidelines/layout)
(80pt sides, 60pt top/bottom).

### Core principles enforced across all screens

1. **Never centre-align multi-line content.** Title and short labels
   may be centered; metadata tables, body text, and action labels are
   always `alignment: .leading`. Sources:
   [Pimp My Type](https://pimpmytype.com/avoid-centered-text/) ·
   [UX Movement](https://uxmovement.com/content/why-you-should-never-center-align-paragraph-text/) ·
   [UXPin](https://www.uxpin.com/studio/blog/alignment-in-design-making-text-and-visuals-more-appealing/).

2. **Single visual hierarchy per surface.** One primary action, one
   accent colour, one largest type element. No competing heroes.
   Sources: [Layout Scene 2026](https://www.layoutscene.com/card-ui-design-patterns-guide-2026/) ·
   [Eleken](https://www.eleken.co/blog-posts/card-ui-examples-and-best-practices-for-product-owners).

3. **Identical row geometry across siblings.** Settings rows, sheet
   form rows, and metadata rows in cards all share row height,
   label-column width, and value-column placement.
   Source: [LearnUI — *3 Pro Tips on Alignment*](https://www.learnui.design/blog/3-pro-tips-on-alignment.html).

4. **8pt grid spacing — no magic numbers.**
   Sources: [Medium / Vitsky — *Comprehensive 8pt Grid Guide*](https://medium.com/swlh/the-comprehensive-8pt-grid-guide-aa16ff402179) ·
   [Spec.fm](https://spec.fm/specifics/8-pt-grid).

5. **Primary vs secondary by tint, not size.** Two same-size buttons,
   one amber (`.borderedProminent`) and one neutral (`.bordered` +
   `.tint(.secondary)`). Source:
   [LogRocket](https://blog.logrocket.com/ux-design/ui-card-design/).

6. **System-native focus chrome on tvOS.** Every focusable control
   uses one of the system button styles (`.borderedProminent` /
   `.bordered` / `.card`) — never a hand-rolled focus halo. Source:
   [Apple HIG — *Focus and Selection*](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection).

7. **Group controls by user task, not by data type.** Settings tabs,
   form sections, and dialog clusters are organised around what the
   user is *trying to accomplish*. Source:
   [Toptal — *How to Improve App Settings UX*](https://www.toptal.com/designers/ux/settings-ux).

## Reading order

Start with **Frame 01** — its rationale establishes the design language
(card layout, typography hierarchy, spacing tokens). The Settings and
Sheet rationales build on that foundation, calling out only the
per-screen specifics.
