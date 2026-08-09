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

## Cross-application v1 closeout

The production-shaped monitor was moved to a dedicated session event-tap
thread while retaining `.defaultTap` and `.commonModes`. A matched event waits
up to 150ms for the main thread to finish `orderOut`; ordinary input stays off
the main thread. The closeout removed the stable-nonfullscreen early-cancel AX
chain, serialized AX cache refreshes into one in-flight read plus one trailing
read, tightened green-button modifiers, used the tracked foreground pid during
handoff, and removed the monitor's actor-unsafe `deinit` cleanup.

- Full unit suite: `703/703`.
- Release binary: universal `arm64 + x86_64`, fixed local certificate.
- 500-event non-target input A/B: disabled `p95 0.191ms / p99 0.258ms`;
  enabled `p95 0.202ms / p99 0.242ms`; both `500/500`, zero tap-disable.
- Valid TextEdit visual pass after waiting for the old process to exit:
  green button `0/3`, Control-Command-F `0/3` visible blinks.

An earlier `3/3 + 3/3` run was invalid: an external defaults toggle was followed
by `pkill` and `open` without waiting for the old process to terminate, so the
new monitor was not proven to exist and no `pending` event was captured. A
controlled restart produced a new pid before the valid pass above.

## Space input probe (2026-08-09)

The one-shot probe used a session `.defaultTap` for `keyDown` / `scrollWheel`,
AppKit global gesture events, a 20ms safe projection of
`SLSCopyManagedDisplaySpaces`, and `activeSpaceDidChange`. It persisted only
display UUID, ordered Space `id64/type`, current Space, abstract arrow direction
and modifier names, and gesture deltas/phases. It did not persist characters,
ordinary key codes, process identities, titles, windows, or raw SkyLight
dictionaries.

- During the dedicated three-finger phase, SkyLight observed 14 real Space ID
  changes and none had a preceding horizontal candidate. AppKit delivered zero
  global gesture events and the session tap stayed enabled. The correct
  fullscreen-to-fullscreen pass (`type 4 -> type 4`) likewise recorded six
  three-finger transitions with no candidate.
- Physical arrow events carry `Fn + NumericPad + nonCoalesced` even when the
  user presses no such extra modifier. After treating those as intrinsic arrow
  flags, exact Control-Left/Right arrived approximately `548-575ms` before the
  Space ID changed. A no-neighbor boundary sample reported
  `possible_targets.exists=false` and expired as `cancelled/no-transition`.
- In the initial adjacent-fullscreen-app visual pass, the owner observed zero
  blinks for three-finger switching (`0/6`) and Control-arrow switching (`0/6`)
  with the probe running, then `0/2` and `0/2` with the probe stopped. This
  visual-only conclusion was later invalidated: a fresh process reproduced the
  blink consistently, and focused telemetry showed `.fullscreen -> Space CG
  false -> SHOW -> AX true -> HIDE`. Three measured visible pulses were about
  `11.3 / 3.4 / 2.2ms`, short enough to fall inside one compositor frame.

The accepted full-to-full fix does not predict user input. When Tungsten is
already confirmed fullscreen, app activation or the Space notification starts
a generation-guarded hold. Transitional false CG/AX verdicts cannot reveal the
panels; `120ms` after the Space notification, CG plus AX makes the final
fullscreen/windowed decision (`500ms` fallback when only activation arrived).
After removing a failed managed-space prediction experiment, the owner verified
on a fresh fixed-certificate Release that both three-finger and Control-arrow
full-to-full switching did not blink, and full-to-windowed restored the taskbar.
Unit suite: `707/707`; Release: universal `arm64 + x86_64`.

Ordinary-Space-to-fullscreen remains unresolved. A managed-space experiment
ordered the panels out about `35ms` before `activeSpaceDidChange`, and a fast AX
probe saw the destination fullscreen around `0.2–1ms` after the notification,
yet the owner still observed `3/3` blinks. Both signals are too late for the
WindowServer transition snapshot, so the experiment was deleted. Three-finger
input still has no usable early event; Control-arrow remains the only measured
early route (`548–575ms`) and no keyboard-only runtime has been accepted.

The final fresh-PID unified-log stream was not persisted because its background
logger exited with the launching shell. This archive therefore retains the
focused telemetry measurements and visual acceptance result, but does not
claim a raw final trace artifact.

Raw evidence and source evolution:

- `TungstenSpaceInputProbe-v1.swift` / `space-input-phase1.jsonl`
- `TungstenSpaceInputProbe-arrow-flags.swift` / `space-input-arrow-flags.jsonl`
- `TungstenSpaceInputProbe-final.swift` / `space-input-keyboard-final.jsonl`
- `space-input-fullscreen-pair.jsonl`
- `space-hold-final-tests.log`
- `space-hold-final-release.log`

Final hold test-log SHA-256:
`8b97aedc4e5d6d3c15213b54be46e123a029a5f69c751360e74bda98bff7bcfa`.
Final hold Release-log SHA-256:
`cddf0177717cb4d2077d2dff2a28837ec74cd2c108c909a67bdb348a5bb83bf2`.

Final source SHA-256:
`28ef6bb7af083e00e466636cd482d3539474c871e83f07d524096d0595e3011d`.
Fullscreen-pair JSONL SHA-256:
`6450b41b05da895a92d6aee25217aac6e34eb35788b138792ebd168dfb24f877`.
