# Changelog

## 0.2.0

- is_effects 0.6.0: `CarriesOutWebRequests.carryOutWebRequest` returning
  `WebRequestOutcome` (formerly `WebDriver.send` and `Sent`, retired by name), and
  `Request.path` a `WebPath`, which cannot name another site.
- The driver as its own service (`dart run is_web_driver:service`), which
  answers only the airlock's user, as the kernel reports it for the socket.
  Each driver is a wall of its own.
- `SocketWebDriver` in `package:is_web_driver/service.dart`: the airlock's
  side, which `CarriesOutWebRequests` and holds no secret.
- Why a destination refused reaches the airlock as a word, not a body, since
  the record keeps it for good. `WebRequestOutcome.refusedBecause` is
  the reply field the sign-in's file names in `refusedBecause`, such as
  `error.code`. A refused token's `Refused` reason carries OAuth's `error`
  code. The whole body is only logged, for whoever runs the driver
  (`SigningWebDriver(log:)`; the service logs to stdout).
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
