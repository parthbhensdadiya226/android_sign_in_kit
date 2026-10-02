import 'dart:convert';

import 'google_scope.dart';

/// The Google account the user picked, with the ID token to send to your
/// server.
///
/// The first fields come from Credential Manager. [id], [emailVerified],
/// [hostedDomain], [issuedAt], [expiresAt], [nonce] and [claims] are read
/// from the ID token itself. They are **not verified** on the device; verify
/// [idToken] on your server before trusting any of them.
class GoogleAccount {
  const GoogleAccount({
    required this.email,
    required this.idToken,
    this.displayName,
    this.givenName,
    this.familyName,
    this.photoUrl,
    this.phoneNumber,
    this.claims = const {},
    this.authorization,
  });

  /// Reads the account sent by the platform, and the claims from its token.
  factory GoogleAccount.fromMap(Map<Object?, Object?> map) {
    final idToken = map['idToken']! as String;
    return GoogleAccount(
      email: map['email']! as String,
      idToken: idToken,
      displayName: map['displayName'] as String?,
      givenName: map['givenName'] as String?,
      familyName: map['familyName'] as String?,
      photoUrl: map['photoUrl'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      claims: _decodeClaims(idToken),
    );
  }

  /// The account's email address.
  final String email;

  /// A signed JWT. Verify it on your server (or pass it to Firebase Auth);
  /// never trust the other fields on their own.
  final String idToken;

  final String? displayName;
  final String? givenName;
  final String? familyName;

  /// The profile picture, if the account has one.
  final String? photoUrl;

  /// Only set for accounts that registered with a phone number.
  final String? phoneNumber;

  /// Every claim in the ID token's payload (`sub`, `email_verified`, `hd`,
  /// `iat`, `exp`, `aud`, `nonce`, ...). Empty if it couldn't be read.
  final Map<String, Object?> claims;

  /// The access granted to the scopes passed to `signInWithGoogle`, or null
  /// when no scopes were asked for or the user declined them.
  final GoogleAuthorization? authorization;

  /// Google's ID for the account (the `sub` claim). Unlike the email, it
  /// never changes, so use it as the user's key in your database.
  String? get id => claims['sub'] as String?;

  /// Whether Google has verified the email address.
  bool? get emailVerified => claims['email_verified'] as bool?;

  /// The Google Workspace domain of the account (e.g. `example.com`), or
  /// null for a personal account.
  String? get hostedDomain => claims['hd'] as String?;

  /// When the ID token was issued.
  DateTime? get issuedAt => _time(claims['iat']);

  /// When the ID token expires (about an hour after [issuedAt]).
  DateTime? get expiresAt => _time(claims['exp']);

  /// The nonce passed to `signInWithGoogle`, as echoed in the token.
  String? get nonce => claims['nonce'] as String?;

  /// A copy with [authorization] set.
  GoogleAccount withAuthorization(GoogleAuthorization? authorization) =>
      GoogleAccount(
        email: email,
        idToken: idToken,
        displayName: displayName,
        givenName: givenName,
        familyName: familyName,
        photoUrl: photoUrl,
        phoneNumber: phoneNumber,
        claims: claims,
        authorization: authorization,
      );

  static DateTime? _time(Object? seconds) => seconds is int
      ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
      : null;

  static Map<String, Object?> _decodeClaims(String idToken) {
    try {
      final payload = idToken.split('.')[1];
      final json = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
      return Map<String, Object?>.from(jsonDecode(json) as Map);
    } on Object {
      return const {};
    }
  }

  @override
  String toString() => 'GoogleAccount($email, $displayName)';
}

/// Access to Google APIs for the requested OAuth scopes.
class GoogleAuthorization {
  const GoogleAuthorization({
    required this.grantedScopes,
    this.accessToken,
    this.serverAuthCode,
    this.email,
  });

  factory GoogleAuthorization.fromMap(Map<Object?, Object?> map) =>
      GoogleAuthorization(
        grantedScopes: [
          for (final scope in map['grantedScopes'] as List? ?? const [])
            _scope(scope as String),
        ],
        accessToken: map['accessToken'] as String?,
        serverAuthCode: map['serverAuthCode'] as String?,
        email: map['email'] as String?,
      );

  /// A short-lived OAuth access token for calling Google APIs from the app.
  final String? accessToken;

  /// The scopes the user granted. Can be fewer than you asked for.
  final List<GoogleScope> grantedScopes;

  /// Only with `offlineAccess`: a one-time code your server exchanges for a
  /// refresh token, to call Google APIs while the user is away.
  final String? serverAuthCode;

  /// The account that granted access, when Google reports it.
  final String? email;

  /// Whether [scope] was granted.
  bool hasScope(GoogleScope scope) => grantedScopes.contains(scope);

  /// Google reports the profile scopes by their short names.
  static GoogleScope _scope(String value) => switch (value) {
    'email' => GoogleScope.email,
    'profile' => GoogleScope.profile,
    _ => GoogleScope(value),
  };

  /// Leaves the tokens out, so they never end up in logs.
  @override
  String toString() => 'GoogleAuthorization($email, $grantedScopes)';
}

/// A username and password picked from the saved passwords sheet.
class SavedPassword {
  const SavedPassword({required this.username, required this.password});

  factory SavedPassword.fromMap(Map<Object?, Object?> map) => SavedPassword(
    username: map['username']! as String,
    password: map['password']! as String,
  );

  /// The id the password was saved with: an email, phone number or username.
  final String username;
  final String password;

  /// Leaves the password out, so it never ends up in logs.
  @override
  String toString() => 'SavedPassword($username)';
}

/// What happened to a password passed to `savePassword`.
enum PasswordSaveResult {
  /// The user saved it (or updated the saved one).
  saved,

  /// It's already in the password manager (saved or picked through this
  /// package before), so no sheet was shown.
  unchanged,

  /// The user closed the sheet or tapped "Not now".
  declined,

  /// Not on Android, so Credential Manager can't save it. With
  /// `autofillHints` on your fields, the iOS keychain or the browser may
  /// still offer to.
  unsupported,
}

/// Why a call failed. A sheet the user closed is not an error: that returns
/// null (or [PasswordSaveResult.declined]).
enum CredentialErrorCode {
  /// Nothing to show: no saved passwords, or no Google account on the
  /// device (or none that used your app before, with `onlyPreviousAccounts`).
  noCredential(
    'There is nothing to show: no saved password for this app, or no '
    'matching Google account on the device.',
  ),

  /// The setup in Google Cloud Console doesn't match the app.
  misconfigured(
    'Google rejected the app. Check that serverClientId is the Web client '
    'ID, and that an Android client with this package name and SHA-1 exists '
    'in the same Google Cloud project.',
  ),

  /// Google Play services, or the Credential Manager provider, is missing
  /// or disabled.
  providerUnavailable(
    'No credential provider is available. Google Play services may be '
    'missing, disabled or out of date.',
  ),

  /// The device doesn't support Credential Manager.
  unsupported('This device does not support Credential Manager.'),

  /// No password manager on the device can save passwords.
  noProvider(
    'No password manager on this device can save passwords. The user can '
    'turn one on in Settings > Passwords, passkeys and accounts.',
  ),

  /// The call was interrupted, for example by the app going to the
  /// background. Trying again usually works.
  interrupted('The request was interrupted. Try again.'),

  /// There was no network connection.
  network('Google could not be reached. Check the internet connection.'),

  /// The Google ID token couldn't be read.
  invalidToken('The Google ID token could not be read.'),

  /// Android returned a different kind of credential than asked for.
  unexpectedCredential('Android returned an unexpected type of credential.'),

  /// There was no foreground activity to show the sheet on.
  noActivity('The app is not in the foreground, so no sheet can be shown.'),

  /// Another `authorize` call is still waiting for the user.
  busy('Another authorization request is still open.'),

  /// Anything else. See [CredentialManagerException.platformMessage].
  unknown('Something went wrong. See platformMessage for details.');

  const CredentialErrorCode(this.description);

  /// What this error means, in plain words. Fine for logs; for users you
  /// probably want your own text.
  final String description;
}

/// Thrown when a call fails for a reason other than the user closing the
/// sheet.
class CredentialManagerException implements Exception {
  const CredentialManagerException(
    this.code, {
    this.platformMessage,
    this.platformType,
    this.statusCode,
  });

  /// The kind of error.
  final CredentialErrorCode code;

  /// What [code] means, in plain words.
  String get message => code.description;

  /// The message from Android or Google Play services, for logs.
  final String? platformMessage;

  /// Android's error type, e.g.
  /// `android.credentials.GetCredentialException.TYPE_NO_CREDENTIAL`, or
  /// the Play services status name (e.g. `NETWORK_ERROR`) for `authorize`.
  final String? platformType;

  /// The Google Play services status code, for `authorize` errors.
  final int? statusCode;

  @override
  String toString() {
    final parts = [
      message,
      if (platformMessage != null) 'platformMessage: $platformMessage',
      if (platformType != null) 'platformType: $platformType',
      if (statusCode != null) 'statusCode: $statusCode',
    ];
    return 'CredentialManagerException(${code.name}): ${parts.join(', ')}';
  }
}
