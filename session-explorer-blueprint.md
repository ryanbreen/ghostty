# Ghostty Session Explorer — Design Blueprint

## Reference
- v0 chat: https://v0.dev/chat/sJem9OKX9rO
- Implementation target: SwiftUI views inside the Ghostty macOS app
- Data source: `~/.config/ghostty/sessions/*.json` (historical) + `SurfaceListSnapshotter.snapshot()` (live)

## Overall Application Shell

A macOS window, 1020px wide × 700px tall, with 12px rounded corners. Dark theme throughout. Background: #0f0f17 (deep blue-black). Window border: 1px at 8% white opacity. Native macOS titlebar with traffic lights.

The window is split horizontally: left sidebar (250px fixed) + main panel (fills remaining width). Separated by a 1px border at #252538.

## Color System

### Surfaces (darkest to lightest)
- Surface-1: #0f0f17 — deepest background
- Surface-2: #13131e — sidebar, titlebar, main header
- Surface-3: #1a1a2e — hover states, separators
- Surface-4: #1e1e2e — selected sidebar row, card backgrounds

### Accent & Status
- Primary accent: #00d4aa (cyan-teal) — selected states, Assert buttons, active badge
- Green: #4ade80 — "Match" status (element exists in current state)
- Red: #f87171 — "Missing" status (element doesn't exist)
- Yellow: #fbbf24 — "Partial" status (some children match, some don't)
- Indigo: #a5b4fc at low opacity — process name pill badges

### Text
- Primary: #e2e2f0 — body text, data values
- Muted: #6e6e88 — timestamps, paths, secondary labels
- Border: #252538 — all separators and card edges

## Typography

Two font families, never mixed:
- **JetBrains Mono** (monospaced) — ALL data: timestamps, counts, tab titles, directories, processes, status labels. Sizes 11-13px.
- **Inter / SF Pro** (system sans) — ALL UI chrome: button labels, section headers, empty state text. Sizes 11-14px.

Weights: 400 regular (data), 500 medium (window title), 600 semibold (badges, primary buttons).

## Left Sidebar (250px)

### Header
"SESSIONS" — 11px uppercase Inter, wide letter-spacing, muted color. 16px horizontal padding, 12px top padding. 1px bottom border.

### Session List (scrollable, fills height between header and bottom button)
Each session row: full width, 12px horizontal padding, 10px vertical. 1px bottom border at 50% opacity.

Row content (vertical stack, 2px gap):
- **Top line**: date in monospace primary ("Apr 10, 08:04"), with "active" badge on right if current
- **Bottom line**: summary in muted monospace ("8 windows, 47 tabs")

**Selected state**: surface-4 background, 2px left border in cyan, date changes to cyan.
**Hover state**: surface-3 background.
**Active badge**: pill shape, cyan bg at 15% opacity, cyan border at 30%, 9px uppercase text.

### "Snapshot Current" Button
Full-width button at sidebar bottom, separated by 1px top border. Cyan border, transparent bg, cyan text. 8px vertical padding, 4px border radius. Hover: cyan bg at 10% opacity. Clicking saves the current Ghostty state to a new session file with auto-generated timestamp filename.

## Main Panel

### Empty State (no session selected)
Centered vertically and horizontally. "Select a session to explore" in 14px muted Inter. A terminal icon above in muted color.

### Header Bar (when session selected)
Surface-2 background, 16px padding, 1px bottom border. Height ~60px.

**Left side (vertical stack):**
- Session timestamp in 14px monospace primary
- Diff summary in 12px monospace muted: "6 windows missing, 2 matching" — the numbers colored with their status colors (red for missing count, green for matching count)

**Right side:**
- "Assert All" button — cyan bg, dark text, 12px horizontal padding, 8px vertical, semibold, 4px radius. This is the primary destructive action. Hover: brighter cyan.

### Window List (scrollable, fills remaining height)
8px padding. Each window from the session is a collapsible card.

## Window Card

### Card Container
Surface-1 background, 1px border at #252538, 6px border radius, 1px bottom margin between cards.

### Card Header Row (always visible, clickable to expand/collapse)
16px horizontal padding, 12px vertical. Flex row with space-between.

**Left side:**
- Expand/collapse chevron (rotates 90° when expanded). Muted color.
- Window title in 13px monospace primary (e.g., "mac")
- Tab count in 12px muted monospace (" — 4 tabs")

**Right side:**
- Status badge: pill shape, 6px horizontal / 2px vertical padding
  - "Match" — green bg at 15%, green text, green border at 30%
  - "Missing" — red bg at 15%, red text, red border at 30%
  - "Partial" — yellow bg at 15%, yellow text, yellow border at 30%
- "Assert Window" button: cyan border, transparent bg, cyan text, 10px horizontal / 6px vertical padding, 4px radius. Only shown when status is NOT "Match".

### Card Body (expanded state)
1px top border. 0px horizontal padding (tabs use full width).

## Tab Row (within expanded window card)

Each tab is a row within the card body. 16px left padding (indented from window level), 12px right padding, 8px vertical padding. 1px bottom border at 50% opacity between tabs.

**Content (horizontal flex):**
- Tab index: 12px monospace muted, 24px wide ("1", "2", "3"...)
- Tab title: 12px monospace primary (e.g., "claude_pulse")
- Split layout: 11px monospace muted, right-aligned before status (e.g., "3 panes, 2-col")
- Status dot: 8px circle, filled with green (#4ade80) if tab matches or red (#f87171) if missing. Right-aligned, 8px right margin.

**If tab has panes (split layout) and window is expanded, show pane rows below:**

## Pane Row (within tab, when tab has splits)

32px left padding (double-indented). 6px vertical padding. No border between panes.

**Content (horizontal flex):**
- Position label: 11px monospace muted, 80px wide (e.g., "left", "right-top", "right-bottom")
- Working directory: 11px monospace muted, fills available width, truncated from head
- Process badge: pill shape, indigo bg at 15%, indigo text at 80%, 11px monospace (e.g., "zsh", "claude", "lazygit")
- Status dot: 6px circle, green or red. Right-aligned.

## Interactive Behaviors

### Expand/Collapse
- Window cards default to **collapsed** (header only visible)
- Click anywhere on the header row to toggle expand/collapse
- Chevron rotates smoothly (0.15s animation)
- Only one window needs to be open at a time? No — allow multiple to be open simultaneously

### Assert Window Button
- Clicking "Assert Window" for a **missing** window:
  1. Pre-assert: auto-snapshot current state (if not already snapshotted this session)
  2. Create the window with all its tabs and pane splits
  3. Each pane starts in the session's recorded working directory
  4. If the session recorded a foreground process (e.g., "claude --resume ..."), optionally run it
  5. After assert: refresh the diff — the window should now show "Match"

- Clicking "Assert Window" for a **partial** window:
  1. Find the existing window by title match
  2. Add missing tabs (in the correct position/order)
  3. For each tab: create missing pane splits
  4. Remove extra tabs that aren't in the session (this is the "assert = assert" semantic)
  5. After assert: refresh diff

### Assert All Button
1. Pre-assert: snapshot current state to `~/.config/ghostty/sessions/pre-assert-<timestamp>.json`
2. For each window in the session:
   - If missing: create it with all tabs/panes
   - If partial: add missing tabs/panes, remove extras
   - If matching: skip (no-op)
3. After all windows asserted: refresh the full diff
4. Note: Assert All does NOT close windows that exist in current state but aren't in the session. It only operates on windows that ARE in the session definition.

### Selection
- Clicking a session row in the sidebar selects it and loads the diff
- Diff computation runs immediately on selection (should be fast — just comparing two JSON trees)
- Live state refreshes every 2 seconds while the explorer is open

### Hover Effects
- Sidebar rows: surface-3 bg on hover
- Buttons: increased opacity or subtle bg fill on hover
- Window card headers: very subtle surface-3 bg on hover

## Diff Algorithm

For each window in the historical session:
1. Match to a current window by title (exact match, case-insensitive)
2. If no title match: try matching by the set of tab working directories (fuzzy)
3. If no match: window is "Missing"
4. If match found: compare tabs
   - For each tab in session: find a matching tab in current window by working directory
   - Tab match = same working directory
   - If all tabs match and split layouts match: window is "Match"
   - If some match: window is "Partial"

For windows in current state that DON'T appear in the session: they are "Extra" — shown at the bottom of the list in a separate "Extra Windows" section with a muted treatment. Assert All leaves them alone.

## Implementation Notes (for Ghostty integration)

### Where this lives
- New SwiftUI file: `macos/Sources/Features/SessionExplorer/SessionExplorerView.swift`
- Supporting model: `macos/Sources/Features/SessionExplorer/SessionDiff.swift`
- Menu integration: add "Session Explorer" menu item (Cmd+Shift+E) in `AppDelegate.swift`
- Window controller: `SessionExplorerWindowController.swift`

### APIs to use (all internal to Ghostty, no IPC needed)
- **Read historical sessions**: `FileManager` reading `~/.config/ghostty/sessions/*.json`
- **Get live state**: `SurfaceListSnapshotter.snapshot()` — already returns JSON of all surfaces
- **Create window**: reuse logic from `handleNewWindowScriptCommand` (AppleScript handler)
- **Create tab**: reuse logic from `handleNewTabScriptCommand`
- **Create split**: reuse logic from `handleSplitScriptCommand`
- **Close tab/window**: reuse logic from `handleCloseScriptCommand`
- **Restore full session**: potentially reuse `handleRestoreSessionScriptCommand` for Assert All

### Session JSON format (from `~/.config/ghostty/sessions/`)
```json
{
  "version": 1,
  "windows": [
    {
      "id": "tab-group-a9d70b660",
      "tabs": [
        {
          "title": "mac",
          "surfaceTree": {
            "root": {
              "split": {
                "direction": "horizontal",
                "ratio": 0.33,
                "left": { "view": { "pwd": "/Users/wrb/mac", "title": "...", "foregroundPid": 99600, "foregroundProcess": "bash" } },
                "right": { "view": { ... } }
              }
            }
          }
        }
      ]
    }
  ]
}
```

### Pre-assert snapshot
Before any destructive assert, call `SurfaceListSnapshotter.snapshot()`, format as the session JSON, and write to `~/.config/ghostty/sessions/pre-assert-<ISO8601>.json`. This is cheap insurance.
