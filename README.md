# is_web_driver

intersyntactic's `WebDriver` (from [is_effects](https://github.com/intersyntactic/effects)):
it sends a `Request` out of the home under one of the person's sign-ins. A
tool describes the request and names a sign-in such as `hart-bot`, and the
airlock decides on it. This driver holds the secret and is the only piece
that ever sees it.

It knows nothing about any destination. A sign-in's kind is a way of
proving who you are, such as OAuth 2 client credentials. Everything a
destination adds sits in that sign-in's file: where its token comes from,
which sites it's for, and which field of a reply names what was made. So
Teams, Slack or GitHub is a file, not a change to this package.

## What a send does

1. **The path stays on its origin.** `path` is appended to `origin`, and the
   driver refuses anything that would name another site. For example,
   `@evil.example` after `https://a.example` reads as a login to
   `evil.example`.
2. **A sign-in goes only to its own sites.** The airlock decides by name
   alone, so it can't know that a sign-in next to an origin outside its file
   would hand a token to a stranger. Only the driver can, and it refuses that
   send.
3. **The driver signs the request.** It does this the way the sign-in's kind
   says, and keeps any token until five minutes before it expires. Concurrent
   sends share a single fetch.
4. **It reads what the destination made.** That becomes `Sent.created`: the
   field the sign-in names, taken from a 2xx JSON reply.

`Ran(Sent)` means the request left the home and got a reply, whatever its
status. `Refused` means nothing reached the destination: an unknown sign-in,
a foreign origin or path, a token the sign-in service wouldn't issue, or a
network failure before any reply.

## Sign-ins

`Credential.load(directory)` reads every file in `directory`, one per
sign-in, each named for its sign-in. That is the layout systemd's
`LoadCredential=` produces in `$CREDENTIALS_DIRECTORY`, where only the
service's user can read the files. The program that runs the driver passes
in that directory. This package never reads the environment.

| kind | signs with | fields |
|---|---|---|
| `client-credentials` | an OAuth 2 bearer token from `tokenUrl` (https only) | `tokenUrl`, `clientId`, `secret`, optional `scope` |

Every kind also takes `origins`, the only sites the sign-in is ever shown
to, and an optional `created`, the reply field naming what was made.

For example, `hart-bot` is a Teams bot. Its `created` is the new activity's
id, which a card press names later:

```json
{
  "kind": "client-credentials",
  "tokenUrl": "https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token",
  "clientId": "<app id>",
  "secret": "<app secret>",
  "scope": "https://api.botframework.com/.default",
  "origins": ["https://smba.trafficmanager.net"],
  "created": "id"
}
```

```dart
final driver = SigningWebDriver(
  await Credential.load(Directory(Platform.environment['CREDENTIALS_DIRECTORY']!)),
);
```
