/// Sends requests out of the home under the person's sign-ins. Holds each
/// sign-in's secret and applies it, so no tool or record ever sees one.
library;

export 'src/credential.dart' show ClientCredentials, Credential;
export 'src/signing_web_driver.dart';
