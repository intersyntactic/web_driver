/// Carries out web requests under the person's sign-ins. Holds each
/// sign-in's secret and applies it, so no tool or record ever sees one.
library;

export 'src/credential.dart' show ClientCredentials, Credential, ReplyField;
export 'src/signing_web_driver.dart';
