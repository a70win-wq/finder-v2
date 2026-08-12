# Finder v2.0 Design QA

## Source truth

- Apple Finder visual reference:
  `/var/folders/ck/w7gkcqhx7vvfm4xhhk1kkdpc0000gp/T/codex-clipboard-0889bf14-149c-4ee0-97a2-6ca6132288bb.png`
- Finder and Finder v2.0 context-menu comparison:
  `/var/folders/ck/w7gkcqhx7vvfm4xhhk1kkdpc0000gp/T/codex-clipboard-85502dfb-4b66-4f0d-bf8b-28d4027d06f0.png`
- Final installed-app capture:
  `/var/folders/ck/w7gkcqhx7vvfm4xhhk1kkdpc0000gp/T/com.openai.sky.CUAService/Finder v2.0 Screenshot 2026-07-31 at 12.02.30 AM.jpeg`
- Same-scale comparison montage:
  `/tmp/FinderV2-design-qa-comparison.png`

The Apple Finder source was captured at 3600 × 2338 pixels (1800 × 1169 points).
Its content area was cropped to 1800 × 1050.5 points and scaled to the final
1316 × 768 app viewport for comparison.

## State coverage

- Light appearance, maximized window, left/right two-pane layout.
- Four-pane grid and three-pane layouts.
- Manually resized pane divider.
- Selected-file and blank-area context menus.
- Sidebar-location context menus and breadcrumb/path context menus.
- Mounted and unmounted external-volume states.
- List sorting from the column header.

## Visual comparison

- Typography: passed. Native AppKit system type, weights and sizes match the
  Finder hierarchy.
- Spacing and alignment: passed. Sidebar rows, compact toolbars, list headers,
  status rows and split dividers align consistently.
- Colors and materials: passed. White semantic content backgrounds, native
  selection colors and restrained separators match the Finder target.
- Icons and thumbnails: passed. Native SF Symbols and file thumbnails are used.
- Copy: passed. Visible labels and actions use concise Traditional Chinese.
- Flexible layouts: passed. Two-, three- and four-pane layouts divide evenly
  and stay aligned when the window changes size. A manual divider adjustment is
  preserved without breaking the other layout ratios.
- Context menu: passed. The app uses native macOS menus and includes Finder-like
  file, blank-area, sidebar-location and breadcrumb/path actions. Google Drive
  sidebar items also show linked/old-folder status, open Google Drive management,
  and hide without deleting the folder. Clicking the current breadcrumb also
  opens a selectable full-path field for copying. The final accessibility tree
  was checked because the Computer Use capture does not expose a screenshot
  while a native menu is open.

## Interaction checks

- Column-header sorting and ascending/descending direction: passed.
- Selected-file and blank-area context menus: passed.
- Layout switching and divider dragging: passed.
- External disk mount and unmount without restarting the app: passed.
- Sync button, work list and undo on temporary folders: passed.
- Native drag-and-drop between panes: not verified in this run; the desktop
  mouse simulator did not trigger the app's drag session.
- Full automated suite: 46 of 46 tests passed.

## Comparison history

The earlier build showed uneven pane sizing after some layout changes and had a
short context menu. The final build adds ratio-aware pane sizing, complete native
menus, live volume updates and clickable list headers. No remaining P0, P1 or P2
visual mismatches were found. Real Google Drive, iCloud File Provider and
physical drag-and-drop still need a direct user-device check.

## Intentional difference

Finder v2.0 keeps multiple folders inside one window, so it retains a compact
shared compare, sync and work-list toolbar that Apple Finder does not have.

final result: passed
