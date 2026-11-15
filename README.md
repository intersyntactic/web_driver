# is_web_driver

intersyntactic's `WebDriver` (from [is_effects](https://github.com/intersyntactic/effects)):
it sends a `Request` out of the home under one of the person's sign-ins. A
tool describes the request and names a sign-in such as `hart-bot`, and the
airlock decides on it. This driver holds the secret and is the only piece
that ever sees it. There is one driver for every web effect. A new
destination, such as Slack, is a new kind of sign-in, not a new driver.

## What a send does

1. **The path stays on its origin.** `path` is appended to `origin`, and the
   driver refuses anything that would name another site. For example,
   `@evil.example` after `https://a.example` reads as a login to
   `evil.example`.
2. **A sign-in goes only to its own sites.** Each kind of credential knows
   the origins it was issued for. The airlock decides by name alone, so it
   can't know that `hart-bot` next to `https://example.com` would hand a
   bot's token to a stranger. Only the driver can, and it refuses that send.
3. **The driver signs the request.** It does this in the sign-in's own way
   and keeps any token until five minutes before it expires. Concurrent sends
   share a single fetch.
4. **It reads what the destination made.** That becomes `Sent.created`, read
   in the sign-in's own way and only from a 2xx reply.

`Ran(Sent)` means the request left the home and got a reply, whatever its
status. `Refused` means nothing reached the destination: an unknown sign-in,
a foreign origin or path, a token the sign-in service wouldn't issue, or a
network failure before any reply.

## Sign-ins

| kind | origins | signs with | `created` |
|---|---|---|---|
| `bot-framework` (a Teams bot) | `https://smba.trafficmanager.net` | client-credentials token for `https://api.botframework.com/.default` from `login.microsoftonline.com/{tenantId}` | the reply's `id`: the new activity, which a card press later names |

## Loading secrets

`Credential.load(directory)` reads every file in `directory`, one per
sign-in, each named for its sign-in. That is the layout systemd's
`LoadCredential=` produces in `$CREDENTIALS_DIRECTORY`, where only the
service's user can read the files. The program that runs the driver passes
in that directory. This package never reads the environment.

```json
{"kind": "bot-framework", "appId": "…", "tenantId": "…", "secret": "…"}
```

```dart
final driver = SigningWebDriver(
  await Credential.load(Directory(Platform.environment['CREDENTIALS_DIRECTORY']!)),
);
```
