# rod.001: HTTP CONNECT tunneling not supported in Crystal stdlib

**Shard:** crystal-stdlib (HTTP::Server)
**Priority:** Medium
**Type:** feature

## Description

Crystal's `HTTP::Server::Response` does not have an `upgrade_to_socket` or equivalent method for handling HTTP CONNECT tunneling. The Go rodney implementation uses `http.Hijacker.Hijack()` to upgrade CONNECT requests to raw TCP tunnels for authenticated proxy support.

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
