# Fullscreen Transition Diagnostics (2026-08-08)

This directory preserves the raw probes and logs that were previously left in
`/private/tmp`. They establish the baseline for the next single-variable panel
experiments.

## Preserved evidence

- `control-window-overlap.log`: current panel collection behavior.
- `noaux-window-overlap.log`: `.fullScreenAuxiliary` removed while retaining
  `.stationary`.
- `mainline-fullscreen-transition-trace.log`: integrated event-driven AX
  experiment.
- `mainline-early-cg-gcd.log`: matching CG window timeline for the integrated
  AX experiment.
- `AXFullscreenTransitionProbe.swift`, `CGAllWindowProbe.swift`, and
  `TungstenWindowProbe.swift`: the exact external probes used to collect the
  logs.

## Established results

- Control overlap: `807844568.522108 - 807844567.746307 = 775.801 ms`.
- No-aux overlap: `807844646.887447 - 807844646.118646 = 768.801 ms`.
- Difference: `7.000 ms`, treated as measurement noise.
- The integrated AX path first showed the fullscreen CG transition window at
  `807846849.405606` and removed the Tungsten panels at `807846849.751136`, an
  overlap of `345.530 ms`.

These results rule out retrying faster Space verdicts, removing
`.fullScreenAuxiliary`, or the same AX window-created/resized path. They do not
test `NSWindowCollectionBehaviorTransient` or `NSWindowSharingNone`.

## Fresh single-variable A/B

The experiments below used one fixed-certificate Release binary. Only
`DOCK_FULLSCREEN_PANEL_EXPERIMENT` changed between launches.

- Fresh control (`behavior=337`, `sharing=1`): the owner observed the blink on
  `3/3` green-button entries and `3/3` Control-Command-F entries.
- Transient (`behavior=329`, `sharing=1`): the owner again observed the blink on
  `3/3` green-button entries and `3/3` Control-Command-F entries.
- `fresh-transient-window-overlap.log` contains seven captured entry episodes
  (one extra entry occurred during the manual run). Their CG overlaps range
  from `748.420 ms` to `835.711 ms`, with a median of `819.982 ms`.

Changing `.stationary` to `.transient` therefore has no measurable or visible
effect on this transition blink.

- Sharing-none (`behavior=337`, `sharing=0`): the owner observed the blink on
  `3/3` green-button entries and `3/3` Control-Command-F entries.
- `fresh-sharing-none-window-overlap.log` contains seven captured entry
  episodes. Their CG overlaps range from `776.958 ms` to `825.348 ms`, with a
  median of `806.594 ms`.

`NSWindowSharingNone` therefore has no measurable or visible effect either.
The capture property does not control whether WindowServer includes the panel
in this native-fullscreen transition.

Both new window-property directions are closed. A future attempt must move to
a signal that reaches the main thread before WindowServer captures the
transition and distinguishes a standard fullscreen intent from ordinary window
creation. Input pre-dispatch prediction remains untested.

## TextEdit input pre-dispatch spike

The default-off `DOCK_FULLSCREEN_INTENT_SPIKE=1` experiment installed a session
event tap for TextEdit's green button and exact Control-Command-F. On a matched
input it synchronously ordered the Tungsten dock and capsule panels out before
returning the event, then kept them hidden under a generation-guarded pending
fullscreen state until confirmation or a two-second timeout.

The same fixed-certificate Release binary was used for both groups:

- Fresh control: the owner observed the blink on `3/3` green-button entries and
  `3/3` Control-Command-F entries.
- Spike green button: the owner observed the blink on `3/3`. The runtime log has
  no `input-hit` before these entries, so the mouse classifier did not arm the
  pending hide. Four captured green-button entry episodes retained `738.946ms`,
  `867.472ms`, `795.484ms`, and `768.528ms` of CG overlap.
- Spike Control-Command-F: the owner observed no blink on `0/3`. Four captured
  shortcut episodes did produce `input-hit` and reduced CG overlap to
  `135.911ms`, `95.101ms`, `194.383ms`, and `186.749ms`.

The shortcut result proved that a pre-dispatch input signal can remove the
owner-visible blink. It did not satisfy the experiment's original machine
criterion: in every captured shortcut entry, Tungsten remained in the CG list
until `95–194ms` after the first fullscreen transition window appeared.

The green-button classifier was then corrected to stop depending on
`mouseEventWindowUnderMousePointer`, which was always `0` in the real samples.
After that correction:

- All four green-button inputs were accepted and confirmed. Intent-to-confirm
  latency was approximately `731 / 764 / 749 / 773ms`.
- The owner observed no blink on `4/4` corrected green-button entries.
- The external CG probe still measured approximately `10 / 50 / 90 / 20ms`
  between the first fullscreen transition window and Tungsten leaving the CG
  list (`10–90ms` range).
- The owner subsequently repeated the focused visual pass and observed
  `0/3` green-button blinks and `0/3` Control-Command-F blinks. Closing every
  TextEdit window produced no false hide for either a click or the shortcut.

The acceptance criterion was deliberately changed after these measurements:
owner-visible `0` blink is authoritative for v1, while the nonzero CG residual
is retained as diagnostic evidence rather than a release blocker. This is a
criterion reversal, not evidence that the original machine criterion passed.
No menu-item modifier samples were collected or validated in this experiment;
menu interception is outside v1.

Raw evidence:

- `intent-spike-control-window-overlap.log`
- `intent-spike-enabled-window-overlap.log`
- `intent-spike-enabled-runtime.log`
- `green-corrected-spike-runtime.log`
- `green-corrected-spike-window-overlap.log`
