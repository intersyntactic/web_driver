# Changelog

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
