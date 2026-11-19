# rod.001: HTTP CONNECT tunneling not supported in Crystal stdlib

**Owner:** webb's `_proxy` command (`src/cli.cr` `proxy_connect`) + crystal-stdlib
**Priority:** Medium
**Type:** feature

**Not actionable in `dsisnero/rod`:** the rod shard has no `rodney` port (zero
`rodney` rows in its ledger, no proxy server under its `src/`). CONNECT belongs
to this repo's consumer CLI plus Crystal's stdlib, so do not re-investigate it
against the shard.

## Description

Crystal's `HTTP::Server::Response` does not have an `upgrade_to_socket` or equivalent method for handling HTTP CONNECT tunneling. The Go rodney implementation uses `http.Hijacker.Hijack()` to upgrade CONNECT requests to raw TCP tunnels for authenticated proxy support.

Verified 2026-11-19 against Crystal 1.22.3: `src/http/` in the stdlib has no
`hijack` symbol at all, so this is still open.

## Impact

The `webb _proxy` internal proxy command cannot handle HTTPS traffic through authenticated proxies. HTTP-only proxying works, but HTTPS CONNECT tunneling requires socket upgrading that Crystal's HTTP server doesn't support.

## Go Reference

`vendor/rodney/main.go:1895-1946` - `proxyConnect` function uses `http.Hijacker.Hijack()` to:
1. Accept CONNECT request
2. Dial upstream proxy
3. Send CONNECT request with auth
4. Hijack client connection
5. Bidirectionally copy data between client and upstream

## Workaround

HTTP-only proxy requests can still be proxied via `HTTP::Client` forwarding. HTTPS requires an alternative approach (e.g., external proxy tool or native Crystal socket handling).

## Related

- Crystal HTTP::Server docs: https://crystal-lang.org/api/HTTP/Server.html
- Go net/http Hijacker: https://pkg.go.dev/net/http#Hijacker
