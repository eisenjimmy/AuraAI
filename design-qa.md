# Aura Workspace Design QA

- Source visual truth: `/var/folders/5g/2h9zh7t91939z858lxlltt740000gn/T/TemporaryItems/NSIRD_screencaptureui_TQXp8C/Screenshot 2026-07-12 at 3.33.37 PM.png`
- Wide implementation capture: `/tmp/aura-codex-clean-wide.png`
- Compact implementation capture: `/tmp/aura-codex-compact.png`
- Viewports: wide desktop and 950 x 700 compact window
- State: dark mode, active conversation, sidebar shown at wide width and automatically hidden at compact width

## Full-view comparison evidence

The implementation now uses one continuous macOS window surface. The sidebar, conversation, and optional preview are separated only by thin structural dividers. The prior nested rounded sidebar shell and detached header treatment are gone. The window-level sidebar toggle sits in the titlebar beside the traffic controls, matching the Codex reference hierarchy.

## Focused comparison evidence

- Titlebar: traffic controls, sidebar toggle, conversation identity, and preview controls occupy one continuous top strip.
- Sidebar: translucent dark material extends through the titlebar and down to the utility actions without an inset card boundary.
- Compact state: below the responsive threshold, the sidebar collapses while the titlebar toggle remains visible and the conversation uses the reclaimed width.
- Resize affordance: divider and window-edge cursor rectangles use native AppKit column/frame resize cursors with expanded hit areas.
- Typography and spacing: native system typography, compact toolbar spacing, neutral selection treatment, and ellipsis behavior remain consistent with the reference.
- Colors and tokens: dark neutral surfaces and gray dividers match the reference; no blue startup focus ring remains.
- Image quality: existing portrait assets remain sharp, circular, and unchanged.
- Copy and content: Aura-specific friend names, roles, and conversation content are intentionally preserved.

## Comparison history

1. P1: the sidebar was rendered as a rounded panel inside a separate titlebar surface. Fixed by removing the nested shell and extending the split content beneath the titlebar.
2. P1: the sidebar toggle was placed inside the conversation header. Fixed by moving it to window chrome beside the traffic controls.
3. P2: narrow windows compressed all panes. Fixed with automatic sidebar collapse at compact widths and hysteresis before restoring it.
4. P2: resize regions lacked cursor feedback. Fixed with explicit native divider, edge, and corner cursor rectangles.

## Residual notes

The compact screenshot contains a macOS removable-volume permission prompt from the temporary QA bundle. It is external to Aura and was excluded from layout judgment; the unobstructed regions verify the responsive shell and collapsed-sidebar state.

## Markdown rendering update

- Source visual truth: `/var/folders/5g/2h9zh7t91939z858lxlltt740000gn/T/TemporaryItems/NSIRD_screencaptureui_yNZqCy/Screenshot 2026-07-12 at 3.47.45 PM.png`
- Implementation verification: the exact Korean source, `**특정 이야기(신데렐라)**를`, now renders through a regression test as `<strong>특정 이야기(신데렐라)</strong>` with no literal `**` text. Inline code and fenced code remain literal.
- Font and typography: bold output is mapped to the native system semibold face by `GFMMarkdownRenderer`.
- Spacing and layout rhythm: unchanged; only inline emphasis tokens are normalized before GFM parsing.
- Colors and visual tokens: unchanged; text remains `labelColor`.
- Image quality and asset fidelity: no image assets affected.
- Copy and content: the exact saved Korean message used in the screenshot is covered by the regression test.

**Findings**

- [P1] Live packaged-app visual capture is blocked.
  Location: Korean release chat surface.
  Evidence: the Mac was locked when the local-app validation workflow attempted to open the rebuilt app.
  Impact: automated tests prove the parser result, but cannot replace a fresh visual screenshot of the packaged chat surface.
  Fix: unlock the Mac and open the rebuilt Korean release once; the saved message will immediately render with bold emphasis and no literal markers.

**Implementation Checklist**

- Completed: normalize paired bold markers outside code before GFM parsing.
- Completed: preserve literal markers inside inline and fenced code.
- Completed: cover Korean particle-adjacent emphasis with a regression test.
- Pending visual capture after the Mac is unlocked.

final result: blocked
