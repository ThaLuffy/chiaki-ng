# Rationale — Frame 01 (Home / HostCard)

Capture: [`01-home.png`](./01-home.png)
Source: [`tvos/ChiakiTV/Views/Components/HostCard.swift`](../../../tvos/ChiakiTV/Views/Components/HostCard.swift)

---

## What changed vs v2

| Element | v2 | v3 | Why |
|---|---|---|---|
| Layout | 3-column HStack (380pt portrait · flex identity · 360pt actions) | HStack(small accent · single-column content) | Multi-column wide cards force the eye to track horizontally between unrelated info. v3 keeps a single vertical reading column. |
| Console portrait | 200×200pt SF Symbol on 380pt column | 88×88pt rounded-square accent | Decorative element should *complement* the content, not dominate it. |
| Title alignment | Inside the identity column (effectively centered between portrait and actions) | Left-aligned at column start | Body text and table content must be left-aligned. |
| Metadata table | "Address" / "ID" / "Origin" with custom font sizes + tracking, label width 110–130pt | "Address" / "MAC" / "Origin", uniform `.body` weight medium, label column 160pt fixed | Visual rhythm requires identical row geometry across rows. |
| Action row | Stacked vertically (Connect on top, trash glyph below) | Horizontal row (Connect prominent + Hide / Wake bordered) | Primary + related secondaries belong in the same band. |
| Spacing | Mixed 32 / 36 / 40pt | Strict 8pt grid: `space2/4/5/6/7` | Multiples of 8 are the industry default. |
| Secondary button tint | Inherited amber from root → amber-on-amber blob | `.tint(.secondary)` (neutral gray) | Two amber buttons next to each other defeat hierarchy. |

---

## Design principles applied

### 1. Never center-align multi-line content

The previous card had its title and metadata column "floating" between the
portrait and action stacks. Visually this read as centered. Multiple sources
explicitly call this out as a readability anti-pattern:

> Center aligned text across multiple lines is exhausting to read because
> the beginning of a new line is always at a slightly different position.
>
> — [Pimp My Type — *Avoid centered text*](https://pimpmytype.com/avoid-centered-text/)

> Without a straight left edge, there is no consistent place where users
> can move their eyes to when they complete each line.
>
> — [UX Movement — *Why You Should Never Center Align Paragraph Text*](https://uxmovement.com/content/why-you-should-never-center-align-paragraph-text/)

> Center alignment should be restricted to short, visually impactful
> elements like titles or quotes.
>
> — [UXPin — *Alignment in Design: A Complete Guide* (2026)](https://www.uxpin.com/studio/blog/alignment-in-design-making-text-and-visuals-more-appealing/)

In v3 every multi-line element — title, state chip, metadata rows, action
row — sits on a single `alignment: .leading` column.

### 2. Single visual hierarchy, no competing accents

The 380pt portrait column was a "second hero" competing with the title for
attention. Modern card-design research recommends one anchor that
complements rather than competes:

> Use color, whitespace, and fonts to create separation and hierarchy …
> overly heavy shadows or borders create visual noise and reduce
> scannability.
>
> — [Layout Scene — *Mastering Card UI Design Patterns for 2026*](https://www.layoutscene.com/card-ui-design-patterns-guide-2026/)

> Cards should structure with the most important content as high or
> large as possible.
>
> — [Eleken — *17 Card UI Design Examples and Best Practices*](https://www.eleken.co/blog-posts/card-ui-examples-and-best-practices-for-product-owners)

v3 puts the title at the top-left as the largest type, then the state
chip directly below, then the metadata table, then the action row. Single
vertical hierarchy.

### 3. 8pt grid spacing — no magic numbers

All paddings and gaps are tokens from `Theme.swift`:

| Token | px | Use in HostCard |
|---|---|---|
| `space2` | 8 | Title ↔ chip vertical gap, metadata-row gap |
| `space4` | 16 | Action-button gap |
| `space5` | 24 | Label ↔ value horizontal gap |
| `space6` | 32 | Header → metadata → action gap (between groups) |
| `space7` | 48 | Outer card padding |

> The principle of 8pt grid uses multiples of 8 (8, 16, 24, 32, 40, 48,
> 56, etc.) for layout, dimensions, padding, and margin of elements.
>
> — [Medium / Vitsky — *The Comprehensive 8pt Grid Guide*](https://medium.com/swlh/the-comprehensive-8pt-grid-guide-aa16ff402179)

> 8pt increments are the right balance of being visually distant while
> having a reasonable number of variables. Most popular screen sizes are
> divisible by 8.
>
> — [Spec.fm — *8-Point Grid*](https://spec.fm/specifics/8-pt-grid)

### 4. tvOS focus-safe spacing between actions

`space4` (16pt) between action buttons is the minimum that prevents focus
halo overlap when tvOS scales the focused button up:

> Be sure to use appropriate spacing between unfocused rows and columns
> to prevent overlap when an item is brought into focus. Include
> appropriate padding between focusable elements. When you use UIKit and
> the focus APIs, an element gets bigger when it comes into focus.
>
> — [Apple HIG — *Focus and Selection*](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)

### 5. Consistent label-value table

The metadata table is a key/value grid. Both columns share an alignment
edge, label column is fixed-width so values stack vertically:

> Related pairs like labels and their inputs should share an alignment.
>
> — [LearnUI — *3 Pro Tips on Alignment*](https://www.learnui.design/blog/3-pro-tips-on-alignment.html)

Labels use `.body.medium` weight with `.secondary` foreground; values use
`.body.monospaced` so digits and hex stack on a vertical baseline.

### 6. Button hierarchy via tint, not size

- **Primary** — `.buttonStyle(.borderedProminent)` inheriting `.tint(amber500)`
  from `applyChiakiTheme()`. The single brand-amber CTA on the screen.
- **Secondary** — `.buttonStyle(.bordered)` with `.tint(.secondary)`
  override. Same control size as Connect, but neutral colour so the
  user's eye doesn't jump between two amber pills.

> Card design should make scannable visual differences between primary
> and secondary actions through colour, not size.
>
> — [LogRocket — *Card interface design: Tutorial, examples, and best practices*](https://blog.logrocket.com/ux-design/ui-card-design/)

---

## Sources

- [Pimp My Type — *Avoid centered text*](https://pimpmytype.com/avoid-centered-text/)
- [UX Movement — *Why You Should Never Center Align Paragraph Text*](https://uxmovement.com/content/why-you-should-never-center-align-paragraph-text/)
- [UXPin — *Alignment in Design: A Complete Guide* (2026)](https://www.uxpin.com/studio/blog/alignment-in-design-making-text-and-visuals-more-appealing/)
- [Layout Scene — *Mastering Card UI Design Patterns for 2026*](https://www.layoutscene.com/card-ui-design-patterns-guide-2026/)
- [Eleken — *17 Card UI Design Examples and Best Practices*](https://www.eleken.co/blog-posts/card-ui-examples-and-best-practices-for-product-owners)
- [Medium / Vitsky — *The Comprehensive 8pt Grid Guide*](https://medium.com/swlh/the-comprehensive-8pt-grid-guide-aa16ff402179)
- [Spec.fm — *8-Point Grid*](https://spec.fm/specifics/8-pt-grid)
- [Apple HIG — *Focus and Selection*](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection)
- [LearnUI — *3 Pro Tips on Alignment*](https://www.learnui.design/blog/3-pro-tips-on-alignment.html)
- [LogRocket — *Card interface design: Tutorial, examples, and best practices*](https://blog.logrocket.com/ux-design/ui-card-design/)
