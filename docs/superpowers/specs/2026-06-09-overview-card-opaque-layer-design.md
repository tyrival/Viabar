# Overview Card Opaque Layer Design

## Summary

Modify `OverviewProjectCard` (macOS `ContentView.swift`) to split content into two layers:
- **Liquid glass layer** (existing): project icon, title, favorite star
- **Opaque card layer** (new): milestone, subtask, reminder, progress ring, percentage

## Motivation

Add visual depth by introducing a solid opaque card that sits on top of the liquid glass, creating a layered material effect.

## Design

### Layout

```
┌──────────────────────────────────────┐
│                                      │  ← Liquid Glass (24pt radius)
│  🔵 Project Title              ★    │  ← Header stays on glass
│                                      │
│  ┌────────────────────────────────┐  │
│  │                                │  │  ← Opaque card
│  │ 📍 Milestone title            │  │    16pt radius, no shadow
│  │   📋 Subtask title           │  │
│  │                                │  │
│  │ 🔔 Reminder date    45% ◔    │  │
│  └────────────────────────────────┘  │
│                                      │  ← Bottom glass margin
└──────────────────────────────────────┘
```

### Spec

| Aspect | Value |
|--------|-------|
| Opaque card background | `ViabarColor.mainPanelBackground` (light=windowBackground, dark=navy) |
| Opaque card corner radius | 16pt |
| Opaque card shadow | None |
| Opaque card border | None |
| Left/right inset | 10pt from liquid glass edge |
| Bottom inset | 10pt from liquid glass edge |
| Top gap from header | 8pt |
| Card total height | Kept at 150pt (may adjust) |

### Content split

**Stays on glass (top):**
- SF Symbol icon + project title + favorite star

**Moves to opaque card:**
- Milestone row (pin icon + title)
- Subtask row (indented list icon + title)
- Reminder label (alarm icon + date)
- Progress ring + percentage text

### Dark/Light support

Opaque card uses `ViabarColor.mainPanelBackground` which already adapts:
- Light: `NSColor.windowBackgroundColor`
- Dark: `NSColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.95)`

## Implementation

Single-file change in `ContentView.swift`: restructure `OverviewProjectCard.body` to wrap the lower content in the opaque card overlay.
