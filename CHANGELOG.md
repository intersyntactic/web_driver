# Changelog

## 0.1.0

- First release: `SigningWebDriver`, the `WebDriver` from `is_effects` that
  holds each sign-in's secret. It signs only for the origins a sign-in's file
  lists, refuses paths that would leave their origin, and fills
  `Sent.created` from the reply field the sign-in names.
- `Credential` and its first kind, `ClientCredentials` (OAuth 2), loaded one
  file per sign-in from systemd's `$CREDENTIALS_DIRECTORY`.
