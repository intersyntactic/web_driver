# Changelog

## 0.2.0

- The driver as its own service (`dart run is_web_driver:service`), which
  answers only the airlock's user, as the kernel reports it for the socket.
  Each driver is a wall of its own.
- `SocketWebDriver` in `package:is_web_driver/service.dart`: the airlock's
  side, a `WebDriver` holding no secret.
- A refusal whose reason only its body gives, such as a non-2xx reply or a
  token the sign-in service would not issue, is logged with that body for
  whoever runs the driver (`SigningWebDriver(log:)`; the service logs to
  stdout). The outcome and the record are unchanged.

## 0.1.0

- First release: `SigningWebDriver`, the `WebDriver` from `is_effects` that
  holds each sign-in's secret. It signs only for the origins a sign-in's file
  lists, refuses paths that would leave their origin, and fills
  `Sent.created` from the reply field the sign-in names.
- `Credential` and its first kind, `ClientCredentials` (OAuth 2), loaded one
  file per sign-in from systemd's `$CREDENTIALS_DIRECTORY`.
