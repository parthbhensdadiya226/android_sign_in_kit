import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'google_scope.dart';
import 'models.dart';

/// Google Sign-In, Google API access (scopes) and saved passwords through
/// Android's Credential Manager.
///
/// Every method can be called from shared code without a platform check.
/// Credential Manager only exists on Android; elsewhere the methods do
/// nothing and return what a closed sheet would (null), so your login screen
/// just carries on. Use [isSupported] to decide whether to show the Google
/// and saved password buttons at all.
abstract final class AndroidSignInKit {
  static const _channel = MethodChannel('android_sign_in_kit');

  /// Set by [initialize]; the defaults for [signInWithGoogle].
  static String? _serverClientId;
  static bool _autoSelect = false;
  static bool _onlyPreviousAccounts = false;

  /// Whether Credential Manager is available (Android only). Handy to hide
  /// buttons that do nothing elsewhere; never needed to avoid errors.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// `autofillHints` for a username field: none on Android, where autofill
  /// would compete with the Credential Manager sheets, and
  /// [AutofillHints.username] elsewhere, so the iOS keychain still fills and
  /// saves logins.
  ///
  /// ```dart
  /// TextField(autofillHints: AndroidSignInKit.usernameAutofillHints)
  /// ```
  static List<String>? get usernameAutofillHints =>
      _hints(AutofillHints.username);

  /// `autofillHints` for a password field. See [usernameAutofillHints].
  static List<String>? get passwordAutofillHints =>
      _hints(AutofillHints.password);

  /// `autofillHints` for a login field that takes an email address. See
  /// [usernameAutofillHints].
  static List<String>? get emailAutofillHints => _hints(AutofillHints.email);

  /// `autofillHints` for the username field of a sign-up form. See
  /// [usernameAutofillHints].
  static List<String>? get newUsernameAutofillHints =>
      _hints(AutofillHints.newUsername);

  /// `autofillHints` for the password field of a sign-up or change-password
  /// form. On iOS this also lets the keychain suggest a strong password.
  /// See [usernameAutofillHints].
  static List<String>? get newPasswordAutofillHints =>
      _hints(AutofillHints.newPassword);

  static List<String>? _hints(String hint) => isSupported ? null : [hint];

  /// Gets the sheets ready in the background, so [signInWithGoogle] and
  /// [getPassword] open them instantly instead of after a short wait. Call
  /// it once, early: in `main()` or when your login screen opens.
  ///
  /// [serverClientId] is your **Web** client ID. Leave it out when the app
  /// has `google-services.json` (Firebase): the ID is then read from it.
  /// [autoSelect] and [onlyPreviousAccounts] become the defaults for
  /// [signInWithGoogle].
  ///
  /// Preparing needs Android 14 or later. On older versions this only
  /// stores the settings, and the sheets open the usual way.
  static Future<void> initialize({
    String? serverClientId,
    bool autoSelect = false,
    bool onlyPreviousAccounts = false,
  }) async {
    _serverClientId = serverClientId;
    _autoSelect = autoSelect;
    _onlyPreviousAccounts = onlyPreviousAccounts;
    await _invoke<void>('initialize', {
      'serverClientId': serverClientId,
      'autoSelect': autoSelect,
      'onlyPreviousAccounts': onlyPreviousAccounts,
    });
  }

  /// Shows the Google account bottom sheet and returns the account the user
  /// picked, or null if they closed the sheet.
  ///
  /// [serverClientId] is the **Web** client ID from Google Cloud Console
  /// (not the Android one). It's the audience of [GoogleAccount.idToken].
  /// Leave it out after [initialize], or when the app has
  /// `google-services.json`.
  ///
  /// With [autoSelect], a user with exactly one account that used your app
  /// before is signed in without a tap. With [onlyPreviousAccounts], the
  /// sheet lists only accounts that signed in to your app before. Both
  /// default to what you passed to [initialize], or false.
  ///
  /// With [useButtonFlow], Google's full-screen "Sign in with Google" flow
  /// is shown instead of the sheet. Use it behind a "Sign in with Google"
  /// button; it also lets the user add an account. [hostedDomain] limits it
  /// to accounts of one Google Workspace domain.
  ///
  /// [nonce] is put into the ID token, so your server can check that the
  /// token was issued for this request.
  ///
  /// With [scopes] (such as [GoogleScope.driveFile]), the user is asked for
  /// access right after signing in, and the result is in
  /// [GoogleAccount.authorization]. See [authorize] for the options.
  ///
  /// Throws a [CredentialManagerException] with
  /// [CredentialErrorCode.noCredential] when the device has no Google
  /// account to show.
  static Future<GoogleAccount?> signInWithGoogle({
    String? serverClientId,
    bool? autoSelect,
    bool? onlyPreviousAccounts,
    bool useButtonFlow = false,
    String? hostedDomain,
    String? nonce,
    List<GoogleScope> scopes = const [],
    bool offlineAccess = false,
  }) async {
    final map = await _invoke<Map<Object?, Object?>>('signInWithGoogle', {
      'serverClientId': serverClientId ?? _serverClientId,
      'autoSelect': autoSelect ?? _autoSelect,
      'onlyPreviousAccounts': onlyPreviousAccounts ?? _onlyPreviousAccounts,
      'useButtonFlow': useButtonFlow,
      'hostedDomain': hostedDomain,
      'nonce': nonce,
    });
    if (map == null) return null;
    final account = GoogleAccount.fromMap(map);
    if (scopes.isEmpty) return account;
    final authorization = await authorize(
      scopes: scopes,
      accountEmail: account.email,
      offlineAccess: offlineAccess,
      serverClientId: serverClientId,
    );
    return account.withAuthorization(authorization);
  }

  /// Signs a returning user in with as little UI as possible, like
  /// `attemptLightweightAuthentication` in google_sign_in. Call it when the
  /// app starts.
  ///
  /// Only accounts that signed in to your app before are offered:
  ///
  /// * one such account, and the user didn't [signOut]: signed in
  ///   automatically, with a brief "Signing in as..." banner;
  /// * several: a sheet listing only those accounts;
  /// * none: returns null right away, without showing anything.
  ///
  /// Returns null too when the user closes the sheet. Then show your normal
  /// login screen.
  static Future<GoogleAccount?> attemptLightweightSignIn({
    String? serverClientId,
    String? nonce,
  }) async {
    try {
      return await signInWithGoogle(
        serverClientId: serverClientId,
        autoSelect: true,
        onlyPreviousAccounts: true,
        nonce: nonce,
      );
    } on CredentialManagerException catch (e) {
      if (e.code == CredentialErrorCode.noCredential) return null;
      rethrow;
    }
  }

  /// Asks for access to Google APIs, with Google's Authorization API.
  ///
  /// Signing in only proves who the user is. To read their Drive files,
  /// calendar or contacts, ask for the matching [scopes], such as
  /// [GoogleScope.driveFile] or [GoogleScope.calendarReadonly]. If the user
  /// granted them before, this returns at once without any UI; otherwise
  /// Google's consent screen is shown. Returns null if the user declines.
  ///
  /// [accountEmail] picks the account (usually [GoogleAccount.email]);
  /// without it, Google asks which one. [hostedDomain] limits it to one
  /// Google Workspace domain.
  ///
  /// With [offlineAccess], [GoogleAuthorization.serverAuthCode] is set: a
  /// code your server exchanges for a refresh token. It needs the Web
  /// client ID ([serverClientId], [initialize] or `google-services.json`).
  /// [forceRefreshToken] asks Google for a new refresh token even if your
  /// server got one before.
  static Future<GoogleAuthorization?> authorize({
    required List<GoogleScope> scopes,
    String? accountEmail,
    String? hostedDomain,
    bool offlineAccess = false,
    bool forceRefreshToken = false,
    String? serverClientId,
  }) async {
    final map = await _invoke<Map<Object?, Object?>>('authorize', {
      'scopes': [for (final scope in scopes) scope.value],
      'accountEmail': accountEmail,
      'hostedDomain': hostedDomain,
      'offlineAccess': offlineAccess,
      'forceRefreshToken': forceRefreshToken,
      'serverClientId': serverClientId ?? _serverClientId,
    });
    return map == null ? null : GoogleAuthorization.fromMap(map);
  }

  /// Asks the user to save a username and password to their password
  /// manager (Google Password Manager by default). Call it after a
  /// successful login or sign-up.
  ///
  /// The sheet only shows when there's something new to save. Android shows
  /// "Save password?" even for a password it already has, so the package
  /// remembers which ones are saved: those saved through this method, and
  /// those picked with [getPassword]. For them nothing is shown and
  /// [PasswordSaveResult.unchanged] is returned, also after the app
  /// restarts. A changed password shows the sheet, so the user can update
  /// it. Only a keyed hash is kept, never the password.
  ///
  /// If your fields use `autofillHints`, it also stops Android autofill from
  /// asking to save the same password a second time.
  ///
  /// On other platforms it returns [PasswordSaveResult.unsupported]. If your
  /// fields have `autofillHints`, it first ends the autofill session, so the
  /// iOS keychain (or the browser) offers to save the password itself.
  static Future<PasswordSaveResult> savePassword({
    required String username,
    required String password,
  }) async {
    if (!isSupported) {
      // No Credential Manager here, but if the fields use autofillHints the
      // system (the iOS keychain, a browser) can still offer to save.
      TextInput.finishAutofillContext();
      return PasswordSaveResult.unsupported;
    }
    // Fields with autofillHints would make Android autofill offer its own
    // "Save password?" dialog when the AutofillGroup goes away. One prompt
    // is enough, so end the autofill session without saving.
    TextInput.finishAutofillContext(shouldSave: false);
    final result = await _invoke<String>('savePassword', {
      'username': username,
      'password': password,
    });
    return PasswordSaveResult.values.asNameMap()[result] ??
        PasswordSaveResult.declined;
  }

  /// Shows the saved passwords for your app in a bottom sheet and returns
  /// the one the user picked, or null if they closed the sheet.
  ///
  /// Pass your [usernameController] and [passwordController] and the picked
  /// login is put into them. Pass [onPicked] (usually your login function)
  /// to log the user in right away; leave it out to only fill the fields
  /// and let the user tap your Log in button:
  ///
  /// ```dart
  /// await AndroidSignInKit.getPassword(
  ///   usernameController: emailController,
  ///   passwordController: passwordController,
  ///   onPicked: (_) => logIn(), // leave out to only fill
  /// );
  /// ```
  ///
  /// [onPicked] runs after the fields are filled, and the returned future
  /// completes after it. Nothing is filled or called when the user closes
  /// the sheet. A later [savePassword] with the picked login won't ask
  /// again.
  ///
  /// Throws a [CredentialManagerException] with
  /// [CredentialErrorCode.noCredential] when nothing is saved for your app.
  static Future<SavedPassword?> getPassword({
    TextEditingController? usernameController,
    TextEditingController? passwordController,
    FutureOr<void> Function(SavedPassword password)? onPicked,
  }) async {
    final map = await _invoke<Map<Object?, Object?>>('getPassword');
    if (map == null) return null;
    final saved = SavedPassword.fromMap(map);
    usernameController?.text = saved.username;
    passwordController?.text = saved.password;
    await onPicked?.call(saved);
    return saved;
  }

  /// Call when the user signs out. It clears the state that `autoSelect`
  /// uses, so the next [signInWithGoogle] shows the sheet again instead of
  /// picking the same account.
  ///
  /// Saved passwords stay saved, so logging in again with the same one
  /// doesn't ask to save it again.
  static Future<void> signOut() => _invoke<void>('signOut');

  /// Forgets the [initialize] settings.
  @visibleForTesting
  static void resetForTesting() {
    _serverClientId = null;
    _autoSelect = false;
    _onlyPreviousAccounts = false;
  }

  /// Calls the Android side. Elsewhere there is nothing to call, so it
  /// returns null: the same as a sheet the user closed.
  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      final details = e.details is Map ? e.details as Map : const {};
      throw CredentialManagerException(
        CredentialErrorCode.values.asNameMap()[e.code] ??
            CredentialErrorCode.unknown,
        platformMessage: e.message,
        platformType: details['type'] as String?,
        statusCode: details['statusCode'] as int?,
      );
    }
  }
}
