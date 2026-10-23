# mvzr (vendored)

This directory contains a copy of [mvzr](https://github.com/mnemnion/mvzr)
v0.3.12, the minimum viable Zig regex library, by mnemnion. See `LICENSE`.

It is vendored because upstream still targets Zig 0.16 and uses array
multiplication (`**`), which was removed in Zig 0.17.0. The only changes made
here are mechanical ports to Zig 0.17 syntax:

* `[1]T{...} ** n` → `@splat(...)`
* array-literal slice coercions adjusted for the stricter 0.17 rules

The library's own test suite passes on Zig 0.17.0 (`zig test vendor/mvzr/mvzr.zig`).
