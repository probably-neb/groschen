- [ ] Make all rendering allocation infallible, i.e. make it panic for now with "OOM". If we're running out of memory while rendering, we're screwed anyway
  - [ ] arena_print
  - [ ] box + signal creation
- [ ] store scroll state on box, eliminate need for separate scroll state in the scrollable widget. Scrollable widget should just use cached tree to determine scroll offset given element heights for virtualized list behavior
```
how does ../raddebugger handle scrolling? Is it integrated in the main `Box` struct in the UI as a field that all ui elements can use?

⏺ Explore(Explore raddebugger UI scrolling)
  ⎿  Done (14 tool uses · 58.6k tokens · 53s)

⏺ Here's how raddebugger handles scrolling:

  Scrolling is integrated into UI_Box — but with two layers

  Per-Box Fields (persistent across frames)

  In src/ui/ui_core.h:365-435, the UI_Box struct has these scroll-related fields:

  Vec2F32 view_off;          // Current animated scroll offset
  Vec2F32 view_off_target;   // Target scroll offset (animation target)
  Vec2F32 view_bounds;       // Bounds of scrollable content

  These are in the "persistent data" section, so they survive across UI rebuilds.

  Box Flags Control Scroll Behavior

  Any box can opt into scrolling via flags:

  UI_BoxFlag_Scroll          // (1<<4) - Raw scroll events in signal
  UI_BoxFlag_ViewScrollX     // (1<<5) - Auto-apply scroll to view offset X
  UI_BoxFlag_ViewScrollY     // (1<<6) - Auto-apply scroll to view offset Y
  UI_BoxFlag_ViewClampX      // (1<<7) - Clamp horizontal scroll
  UI_BoxFlag_ViewClampY      // (1<<8) - Clamp vertical scroll

  Two Processing Paths

  1. ViewScroll flags — The framework automatically updates view_off_target on scroll events. During layout, children are offset by view_off:
  child->rect.p0.v[axis] -= floor_f32(box->view_off.v[axis]);
  1. This is the "any box can scroll" path.
  2. Scroll flag — Raw scroll deltas are exposed in UI_Signal.scroll (Vec2S16) for widgets to consume manually.

  Animation

  view_off animates toward view_off_target each frame using scroll_animation_rate, converging when within ~2px.

  High-Level Widget

  There's also a dedicated ui_scroll_list_begin/end compound widget that builds on top of this system — it creates a scrollable container, manages row-based scrolling via UI_ScrollPt (index + fractional offset), and renders scroll
  bars. But the underlying mechanism is still the same box flags + view_off system.

  Summary

  Yes, scrolling is integrated into the UI_Box struct as fields available to all boxes. Any box can become scrollable by adding ViewScroll flags. The dedicated scroll list widget is a convenience built on top of this per-box
  capability, not a separate system.
```
- [ ] Update scroll demo to use multi-line boxes and test horizontal scrolling as well
