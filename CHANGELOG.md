# Changelog

## 0.5.0

- is_effects ^0.11.0. A 2xx response's body comes back as `Request.keep`
  asks: `NoBody`, `TextBody` or `BytesBody`. `maxBodyBytes` (16 MiB by
  default) caps what is read; keeping a body over it is `Refused`, as is
  keeping text that isn't UTF-8.
- A GET's redirect is followed, only to a site in the sign-in's file (or,
  with no sign-in, the site decided), for at most three hops, and every hop
  is named in `WebResponse.redirects` without its query. The sign-in's
  secret goes only to the site decided, never across a hop. Any other
  redirect is `Refused`; a non-GET still gets its redirect as the answer.
- **Breaking:** `HttpCall` takes a fifth argument, the most body bytes to
  read, and `HttpResult` is `({int status, Uint8List? body, Uri? location})`:
  the body as bytes, null when over that limit.

## 0.4.2

- `httpCall` no longer follows redirects. A 3xx comes back as the response's
  status, so a request goes only to the site it was decided for, and the
  record shows where it went. `dart:io` followed GET and HEAD redirects, and
  a POST's 303, to any site, up to five hops, and the record never showed it.

## 0.4.1

- `WebRequestDriverSocket(socket, checkDriver:)`: an optional `CheckDriver`
  that runs on each connected socket before the request is written. A
  reason it returns becomes `Refused` and the driver never sees the request.
  The airlock uses it to check which release the kernel says the driver is.

## 0.4.0

- Renamed from `is_web_driver`: the package is `is_web_request_driver`, and
  `WebDriver`, `WebDriverService` and `WebDriverSocket` are
  `WebRequestDriver`, `WebRequestDriverService` and `WebRequestDriverSocket`.
  `WebDriver` is already the W3C name for browser automation. The service
  reads `WEB_REQUEST_DRIVER_SOCKET` and `WEB_REQUEST_DRIVER_CALLER` in place
  of `WEB_DRIVER_SOCKET` and `WEB_DRIVER_CALLER`.
- is_effects ^0.9.0: `carryOutWebRequest` returns `Outcome<WebResponse>`
  (formerly `WebRequestOutcome`), and the socket uses `encodeWebResponse` and
  `decodeWebResponse`. The JSON is unchanged, so a 0.3.0 driver and a 0.4.0
  airlock still understand each other.

## 0.3.0

- is_effects ^0.8.0. The API is unchanged, but it takes and returns
  is_effects types, so it can't share a project with is_effects 0.7. The
  socket's JSON is byte for byte the same, so a 0.2.0 driver and a 0.3.0
  airlock still understand each other.

## 0.2.0

- One web driver and its socket: `SigningWebDriver` is `WebDriver`, the web
  driver itself, holding the secrets; `SocketWebDriver` is `WebDriverSocket`,
  the airlock's side of the web driver's socket. The old names said there
  were two kinds of web driver.
- is_effects 0.7.0: `CarriesOutWebRequests.carryOutWebRequest` returning
  `WebRequestOutcome` (formerly `WebDriver.send` and `Sent`, retired by name), and
  `Request.path` a `WebPath`, which cannot name another site.
- The driver as its own service (`dart run is_web_driver:service`), which
  answers only the airlock's user, as the kernel reports it for the socket.
  Each driver is a wall of its own.
- `WebDriverSocket` in `package:is_web_driver/service.dart`: the airlock's
  side, which `CarriesOutWebRequests` and holds no secret.
- Why a destination refused reaches the airlock as a word, not a body, since
  the record keeps it for good. `WebRequestOutcome.refusedBecause` is
  the reply field the sign-in's file names in `refusedBecause`, such as
  `error.code`. A refused token's `Refused` reason carries OAuth's `error`
  code. The whole body is only logged, for whoever runs the driver
  (`WebDriver(log:)`; the service logs to stdout).
- `created` and `refusedBecause` are `ReplyField`s, paths of keys into a JSON
  reply, checked when the sign-in's file loads.
- The socket speaks is_effects' own JSON for `Request` and
  `Outcome<WebRequestOutcome>`, shared with the airlock, in place of this
  package's own codec. An answer it can't read is `Refused`, never guessed at.

## 0.1.0

- First release: `SigningWebDriver`, the `WebDriver` from `is_effects` that
  holds each sign-in's secret. It signs only for the origins a sign-in's file
  lists, refuses paths that would leave their origin, and fills
  `Sent.created` from the reply field the sign-in names.
- `Credential` and its first kind, `ClientCredentials` (OAuth 2), loaded one
  file per sign-in from systemd's `$CREDENTIALS_DIRECTORY`.
