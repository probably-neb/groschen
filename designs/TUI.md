# Terminal UI Design

> Create distinctive, production-grade terminal user interfaces with high design quality.
> Use this skill when building CLI tools, TUI applications, or terminal-based interfaces.

---

## Design Thinking

Before coding, commit to a bold aesthetic direction by considering:

1. **Purpose** — What problem does this interface solve? Who uses it? What's the workflow?
2. **Tone** — Choose an extreme aesthetic direction (see options below)
3. **Constraints** — Technical requirements
4. **Differentiation** — What makes this unforgettable? What's the one thing users will remember?

**Tone Options:**
Hacker/Cyberpunk, Retro-computing (80s/90s), Minimalist Zen, Maximalist Dashboard, Synthwave Neon, Monochrome Brutalist, Corporate Mainframe, Playful/Whimsical, Matrix-style, Steampunk Terminal, Vaporwave, Military/Tactical, Art Deco, Paper-tape Nostalgic

> **Core principle:** Intentionality matters more than intensity. Both dense dashboards and zen single-focus interfaces work when executed with precision.

---

## Box Drawing & Borders

| Style | Characters | Feel |
|---|---|---|
| Single line | `┌─┐│└┘` | Clean, modern |
| Double line | `╔═╗║╚╝` | Bold, formal, retro-mainframe |
| Rounded | `╭─╮│╰╯` | Soft, friendly, modern |
| Heavy | `┏━┓┃┗┛` | Strong, industrial |
| Dashed/Dotted | `┄┆` | Light, airy, informal |
| ASCII only | `+-+\|` | Retro, universal compatibility |
| Block chars | `█▀▄▌▐` | Chunky, bold, brutalist |
| Custom Unicode | `◢◣◤◥ ●○◐◑ ▲▼◀▶` | Unique frames |

Avoid defaulting to simple single-line boxes. Consider asymmetric borders, double-thick headers, or decorative corners like `◆ ◈ ✦ ⬡`.

---

## Color & Theme

Commit to a cohesive palette using these strategies:

### Color Depth Options

- **ANSI 16** — Classic, universal combinations beyond default red/green/blue
- **256-color** — Rich palettes with gradients and subtle background variations
- **True color (24-bit)** — Full spectrum with gradient text and smooth transitions
- **Monochrome** — Single color with intensity variations (dim, normal, bold, reverse)

### Atmosphere Creation

- Background color blocks for sections
- Gradient fills using block characters (`░▒▓█`)
- Color-coded semantic meaning (avoid cliched red=bad, green=good)
- Inverted/reverse video for emphasis
- Dim text for secondary information, bold for primary

### Palette Examples

| Theme | Colors | Aesthetic |
|---|---|---|
| Cyberpunk | `#ff00ff` `#00ffff` `#1a0a2e` bg | Hot pink + electric cyan on deep purple |
| Amber terminal | `#ffb000` on black | Vintage CRT aesthetic |
| Nord-inspired | Cool blues, muted greens | Dark blue-gray background |
| Hot Dog Stand | Yellow + Red | Intentionally garish (playful/ironic UIs) |

---

## Typography & Text Styling

The terminal is entirely typography-based. Make it count.

### Text Techniques

- **ASCII art headers** — Figlet-style banners, custom letterforms, Unicode art
- **Text weight** — Bold, dim, normal for visual hierarchy
- **Text decoration** — Underline, strikethrough, italic (where supported)
- **Letter spacing** — Simulate with spaces for headers (`H E A D E R`)
- **Case** — ALL CAPS for headers, lowercase for body, mixed for emphasis
- **Unicode symbols** — `→ • ◆ ★ ⚡ λ ∴ ≡ ⌘`
- **Custom bullets** — `▸ ◉ ✓ ⬢ ›` or themed symbols

### ASCII Art Styles

```
Block:   ███████╗██╗██╗ ███████╗
Slant:   /___  / / // / / ____/
Small:   ╔═╗┌─┐┌─┐
Minimal: [ HEADER ]
```

---

## Layout & Spatial Composition

Break free from single-column output:

- **Panels & Windows** — Create distinct regions with borders
- **Columns** — Side-by-side information using careful spacing
- **Tables** — Align data meaningfully using Unicode table characters
- **Whitespace** — Generous padding inside panels, breathing room between sections
- **Density** — Match to purpose (dashboards=dense, wizards=sparse)
- **Hierarchy** — Clear visual distinction between primary content, secondary info, and chrome
- **Asymmetry** — Off-center titles, weighted layouts, unexpected alignments

---

## Motion & Animation

Terminals support dynamic content:

- **Spinners** — Beyond basic `|/-\`. Use Braille patterns (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) or dots (`⣾⣽⣻⢿⡿⣟⣯⣷`)
- **Progress bars** — `▓░`, `█▒`, `[=====> ]`, or creative alternatives like `◐◓◑◒`
- **Typing effects** — Reveal text character-by-character for drama
- **Transitions** — Wipe effects, fade in/out with color intensity
- **Live updates** — Streaming data, real-time charts

---

## Data Display

- **Sparklines** — `▁▂▃▄▅▆▇█` for inline mini-charts
- **Bar charts** — Horizontal bars with block characters
- **Tables** — Smart column sizing, alternating row colors, aligned numbers
- **Trees** — `├── └── │` for hierarchies
- **Status indicators** — `●` green, `○` empty, `◐` partial, `✓` complete, `✗` failed
- **Gauges** — `[████████░░]` with percentage

---

## Decorative Elements

Add character without clutter:

- **Dividers** — `───── ═════ •••••• ░░░░░░ ≋≋≋≋≋≋`
- **Section markers** — `▶ SECTION`, `[ SECTION ]`, `─── SECTION ───`, `◆ SECTION`
- **Background textures** — Patterns using light characters like `· ∙ ░`
- **Icons** — Nerd Font icons if available

---

## Anti-Patterns to Avoid

**NEVER** use generic terminal aesthetics:

- Plain unformatted text output
- Default colors without intentional palette
- Basic `[INFO]`, `[ERROR]` prefixes without styling
- Simple `----` dividers
- Walls of unstructured text
- Generic progress bars without personality
- Boring help text formatting
- Inconsistent spacing and alignment

---

## ANSI Escape Codes

| Code | Effect |
|---|---|
| `\x1b[1m` | Bold |
| `\x1b[3m` | Italic |
| `\x1b[4m` | Underline |
| `\x1b[31m` | Red foreground |
| `\x1b[38;2;R;G;Bm` | True color |
| `\x1b[2J` | Clear screen |

---

> **The terminal is a canvas with unique constraints and possibilities. Don't just print text — craft an experience.**
>
> Match implementation complexity to aesthetic vision. Dense monitoring dashboards need elaborate panels and live updates. Minimal CLIs need restraint, precision, and perfect alignment. Elegance comes from executing the vision well.
