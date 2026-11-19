# rod.002: WaitStable waits a fixed duration instead of network idle

**Shard:** `lib/rod` (`dsisnero/rod`, local patch)
**Priority:** Medium
**Type:** behavior gap

## Description

go-rod's `Page.WaitStable(d)` waits on three things in parallel: `WaitLoad`,
`WaitRequestIdle(d)`, and `WaitDOMStable(d, 0)`. The Crystal port in
`lib/rod/src/rod/page.cr` replaces the middle branch with `wait_duration(d)`:

```crystal
# lib/rod/src/rod/page.cr (wait_stable)
spawn { wait_load }
spawn { wait_duration(d) }        # go-rod: p.WaitRequestIdle(d, nil, nil, nil)()
spawn { wait_dom_stable(d, 0.0) }
```

`wait_request_idle` exists in the same file but is not called here.

## Impact

`webb waitstable` (Go `cmdWaitStable` → `page.MustWaitStable()` →
`WaitStable(time.Second)`) returns after one second of DOM stability even when
the page still has in-flight requests. Go would wait for the request queue to
go idle first. Both still take at least one second, so the command's output and
exit status match; only pages with slow background requests can differ.

This is why `main.go::function::cmdWaitStable` is signed off against the
one-second contract rather than full network-idle parity.

## Go Reference

- `vendor/rodney/main.go:1067-1071` — `cmdWaitStable` calls `MustWaitStable()`
- go-rod `must.go:449` — `MustWaitStable()` is `WaitStable(time.Second)`
- go-rod `page.go:821` — `WaitStable` runs `WaitLoad`, `WaitRequestIdle(d)`,
  `WaitDOMStable(d, 0)` concurrently

## Reproduction

1. Serve a page that starts a request lasting ~5 seconds.
2. Run `webb waitstable` against it and time the command.
3. Crystal returns after ~1s; go-rod waits ~5s for the request queue to idle.

## Fix

Call `wait_request_idle(d, nil, [] of String, nil)` in place of
`wait_duration(d)` inside `Page#wait_stable`, then re-run the rod shard's
parity suite and `make test` here.
