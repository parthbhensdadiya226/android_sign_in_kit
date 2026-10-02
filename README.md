# android_sign_in_kit

[![pub package](https://img.shields.io/pub/v/android_sign_in_kit.svg)](https://pub.dev/packages/android_sign_in_kit)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/parthbhensdadiya226/android_sign_in_kit/blob/main/LICENSE)

Google Sign-In with Android's account bottom sheet, Google API scopes, and saving and picking passwords, through Android's [Credential Manager](https://developer.android.com/identity/credential-manager).

This is an independent package, not an official Google plugin.

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/parthbhensdadiya226/android_sign_in_kit/main/doc/google_sheet.png" width="200" alt="The Google account bottom sheet"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/parthbhensdadiya226/android_sign_in_kit/main/doc/details.png" width="200" alt="Signed in, with the details from the Google ID token"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/parthbhensdadiya226/android_sign_in_kit/main/doc/password_sheet.png" width="200" alt="The saved passwords bottom sheet"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/parthbhensdadiya226/android_sign_in_kit/main/doc/save_sheet.png" width="200" alt="The Save password sheet"></td>
  </tr>
  <tr>
    <td align="center">Google Sign-In</td>
    <td align="center">Account details</td>
    <td align="center">Saved passwords</td>
    <td align="center">Save password</td>
  </tr>
</table>

```dart
AndroidSignInKit.initialize(serverClientId: webClientId); // once, in main()

final account = await AndroidSignInKit.signInWithGoogle();
final saved = await AndroidSignInKit.getPassword();
await AndroidSignInKit.savePassword(username: email, password: password);
await AndroidSignInKit.signOut();
```

## Contents

- [Why this package](#-why-this-package)
- [Getting started](#-getting-started)
- [Initialize once](#-initialize-once)
- [Google Sign-In](#-google-sign-in)
- [Lightweight sign-in for returning users](#-lightweight-sign-in-for-returning-users)
- [Scopes: access to Google APIs](#-scopes-access-to-google-apis)
- [Saving and picking passwords](#-saving-and-picking-passwords)
- [Autofill hints](#%EF%B8%8F-autofill-hints)
- [Signing out](#-signing-out)
- [Errors](#%EF%B8%8F-errors)
- [Password managers other than Google's](#%EF%B8%8F-password-managers-other-than-googles)
- [Release builds](#-release-builds)
- [iOS and other platforms](#-ios-and-other-platforms)

## 💡 Why this package

| | |
|---|---|
| **The account bottom sheet** | The user sees the Google accounts on the phone and picks one. Nobody is signed in to an account they didn't choose. |
| **Opens instantly** | `initialize()` gets the sheets ready in the background, so they open on tap instead of after a pause. |
| **Everything Google sends** | Name, email, photo, phone, plus the claims in the ID token: Google user ID, email verified, Workspace domain, expiry. |
| **Scopes** | Ask for access to Drive, Calendar or any Google API, with or without a server auth code. |
| **Lightweight sign-in** | Signs a returning user in on app start with no taps, or does nothing. |
| **Save password, only when it's new** | Android asks "Save password?" even for a password it already has. The package doesn't. |
| **Typed errors** | One `CredentialManagerException` with a `code`, a plain-words `message`, and Android's own message and type. |
| **No platform checks** | Every method is safe on iOS, web and desktop, so shared code needs no `Platform.isAndroid`. |
| **Firebase-ready** | With `google-services.json` in the app, you don't need to pass the Web client ID at all. |

## 🚀 Getting started

### Requirements

- Flutter 3.32 or later
- Android `minSdk` 24 or later
- Google Play services on the device (on Android 14 and later the system handles it)

### Install

```bash
flutter pub add android_sign_in_kit
```

Passwords work right away. Google Sign-In and scopes need the setup below.

### Google Cloud setup (once)

1. Open [Google Cloud Console](https://console.cloud.google.com) and pick or create a project.
2. **APIs & Services → OAuth consent screen**: fill in the app name and your email. While the app is in testing, add your Google account under **Test users**. This app name is what Google shows on its consent screen for scopes.
3. **Credentials → Create credentials → OAuth client ID → Android**: enter your app's package name (`applicationId`) and SHA-1.
4. **Credentials → Create credentials → OAuth client ID → Web application**: just create it. Its **Client ID** is the `serverClientId`.

Get the SHA-1 of your debug key with:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android
```

In **Credentials**, check the **Type** column: the ID you use must say *Web application*. Passing an Android client ID is the most common mistake, and it fails with `misconfigured`.

Your app needs both clients, but your code only uses the **Web** client ID. The Android client is how Google recognises your app by its package name and SHA-1. The Web client ID isn't a secret; it ships inside your app.

### Using Firebase?

Firebase already made both clients for you, and `google-services.json` contains the Web client ID. If your app applies the `com.google.gms.google-services` Gradle plugin (`flutterfire configure` sets that up), you don't need to pass `serverClientId` anywhere: the package reads it from the `default_web_client_id` resource that the plugin generates.

```dart
AndroidSignInKit.initialize(); // no client ID needed
```

Add your SHA-1 in **Firebase console → Project settings → Your apps**. To sign in to Firebase, pass the ID token on:

```dart
final account = await AndroidSignInKit.signInWithGoogle();
if (account != null) {
  await FirebaseAuth.instance.signInWithCredential(
    GoogleAuthProvider.credential(idToken: account.idToken),
  );
}
```

## ⚡ Initialize once

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AndroidSignInKit.initialize(
    serverClientId: '1234-abc.apps.googleusercontent.com', // or leave out with Firebase
  );
  runApp(const MyApp());
}
```

Without it, a sheet takes a moment to appear while Android looks up the accounts and passwords. `initialize` does that lookup in the background ahead of time, and again after each sheet, so the sheet opens as soon as the user taps. On a Galaxy A36 the Google sheet appeared in about 0.35 s instead of 0.7 to 1.1 s.

It also stores the client ID and the default options, so the other calls don't need them. Preparing needs Android 14 or later; on older versions the sheets open the usual way.

## 🔐 Google Sign-In

```dart
final account = await AndroidSignInKit.signInWithGoogle();
if (account == null) return; // the user closed the sheet

await myServer.signIn(account.idToken); // verify the token on your server
```

The sheet lists the Google accounts on the phone, with your app's name from `android:label` in its title.

### What you get

| Field | From | |
|---|---|---|
| `email` | Credential Manager | The account's email. |
| `idToken` | Credential Manager | A signed JWT. Send it to your server and verify it there. |
| `displayName`, `givenName`, `familyName` | Credential Manager | The account's name. |
| `photoUrl` | Credential Manager | The profile picture, if there is one. |
| `phoneNumber` | Credential Manager | Only for accounts made with a phone number. |
| `id` | ID token (`sub`) | Google's ID for the account. Unlike the email it never changes, so use it as the user's key. |
| `emailVerified` | ID token | Whether Google verified the email. |
| `hostedDomain` | ID token (`hd`) | The Google Workspace domain, or null for a personal account. |
| `issuedAt`, `expiresAt` | ID token | When the token was made and when it expires (an hour later). |
| `nonce` | ID token | The nonce you passed in. |
| `claims` | ID token | Every claim in the token, as a map. |
| `authorization` | Authorization API | The granted scopes, when you asked for any. |

The token fields are read on the device and **not verified**; they're for display and convenience. Your server must verify `idToken` before trusting anything in it.

### Options

| Option | Default | What it does |
|---|---|---|
| `serverClientId` | from `initialize` or `google-services.json` | Your **Web** client ID. |
| `autoSelect` | from `initialize`, else `false` | Signs a returning user in without a tap, when exactly one account used your app before and they didn't sign out. |
| `onlyPreviousAccounts` | from `initialize`, else `false` | Lists only the accounts that signed in to your app before. |
| `useButtonFlow` | `false` | Shows Google's full-screen "Sign in with Google" flow instead of the sheet. Use it behind a "Sign in with Google" button. It also lets the user add an account to the phone. |
| `hostedDomain` | `null` | With `useButtonFlow`, only accounts of this Google Workspace domain. |
| `nonce` | `null` | Put into the ID token, so your server can check the token was made for this request. A call with a nonce can't use the prepared sheet. |
| `scopes` | none | OAuth scopes to ask for right after sign-in. See [Scopes](#-scopes-access-to-google-apis). |
| `offlineAccess` | `false` | With `scopes`, also get a server auth code. |

### Sheet or button flow?

- **Sheet** (default): fast and light. Good for a login screen. If the phone has no Google account it throws `noCredential`.
- **Button flow**: what users expect after tapping a "Sign in with Google" button. Always shows something, even with no account on the phone.

## 🪶 Lightweight sign-in for returning users

Like `attemptLightweightAuthentication` in google_sign_in. Call it when the app starts:

```dart
final account = await AndroidSignInKit.attemptLightweightSignIn();
if (account != null) {
  // A returning user: go straight to the home screen.
} else {
  // Show your login screen.
}
```

It only offers accounts that signed in to your app before:

| Accounts that used your app before | What happens |
|---|---|
| None | Returns `null` at once. Nothing is shown. |
| One, and the user didn't sign out | Signed in automatically, with a short "Signing in as…" banner. |
| One after `signOut`, or several | A sheet with only those accounts. One tap signs in. |

Closing that sheet also returns `null`.

## 🔓 Scopes: access to Google APIs

Signing in proves who the user is. To call a Google API for them (Drive, Calendar, Gmail, YouTube…), ask for its OAuth scopes. Credential Manager can't do this, so the package uses Google's Authorization API for it.

```dart
final authorization = await AndroidSignInKit.authorize(
  scopes: [GoogleScope.driveFile],
  accountEmail: account.email,
);
if (authorization == null) return; // the user declined

final response = await http.get(
  Uri.parse('https://www.googleapis.com/drive/v3/files'),
  headers: {'Authorization': 'Bearer ${authorization.accessToken}'},
);
```

If the user granted the scopes before, `authorize` returns at once without any UI. Otherwise Google shows its consent screen with the app name from your OAuth consent screen.

You can also ask for scopes as part of sign-in:

```dart
final account = await AndroidSignInKit.signInWithGoogle(
  scopes: [GoogleScope.calendarReadonly],
);
final token = account?.authorization?.accessToken;
```

If the user signs in but declines the scopes, you still get the account, with `authorization` set to `null`.

### Picking scopes

`GoogleScope` has constants for the common ones, so you pick them like an enum:

| Area | Constants |
|---|---|
| Profile | `email`, `profile`, `birthday`, `phoneNumbers`, `gender`, `addresses` |
| Drive | `driveFile`, `driveAppData`, `driveReadonly`, `drive` |
| Docs and Sheets | `documentsReadonly`, `documents`, `spreadsheetsReadonly`, `spreadsheets` |
| Calendar | `calendarReadonly`, `calendarEvents`, `calendar` |
| Contacts | `contactsReadonly`, `contacts` |
| Gmail | `gmailSend`, `gmailReadonly`, `gmailModify` |
| Tasks | `tasksReadonly`, `tasks` |
| YouTube | `youtubeReadonly`, `youtube` |

Google has hundreds more, so it isn't a closed Dart `enum`: any other scope works by its URL, for example `GoogleScope('https://www.googleapis.com/auth/fitness.activity.read')`. See [Google's list of scopes](https://developers.google.com/identity/protocols/oauth2/scopes).

| `GoogleAuthorization` | |
|---|---|
| `accessToken` | Short-lived token for calling Google APIs from the app. |
| `grantedScopes` | What the user granted. Can be less than you asked for; check with `hasScope(GoogleScope.driveFile)`. |
| `serverAuthCode` | Only with `offlineAccess: true`: a one-time code your server exchanges for a refresh token, to call Google APIs while the user is away. |
| `email` | The account that granted access. |

| `authorize` option | |
|---|---|
| `scopes` | The OAuth scopes. |
| `accountEmail` | Which account. Without it, Google asks. |
| `hostedDomain` | Only accounts of this Google Workspace domain. |
| `offlineAccess` | Also return `serverAuthCode`. Needs the Web client ID. |
| `forceRefreshToken` | Ask Google for a new refresh token even if your server got one before. |

Sensitive scopes (Gmail, full Drive…) show an "unverified app" warning until Google verifies your app. `drive.file` and the profile scopes don't.

## 🔑 Saving and picking passwords

### Save after login

Call `savePassword` after your login or sign-up call succeeds:

```dart
await myServer.logIn(email, password);

final result = await AndroidSignInKit.savePassword(
  username: email,
  password: password,
);
```

| `result` | What happened |
|---|---|
| `PasswordSaveResult.saved` | The "Save password?" sheet showed and the user saved it (or updated a changed password). |
| `PasswordSaveResult.unchanged` | The password is already saved, so no sheet was shown. |
| `PasswordSaveResult.declined` | The user tapped "Cancel" or closed the sheet. |
| `PasswordSaveResult.unsupported` | Not on Android. See [iOS and other platforms](#-ios-and-other-platforms). |

**Why `unchanged` matters.** Android shows "Save password?" every time an app asks, even for a password that's already saved, and apps can't check what's saved without showing a sheet. So the package remembers which logins are already in the password manager: ones saved with `savePassword` and ones picked with `getPassword`. For those it doesn't ask again, even after the app restarts. A changed password isn't known, so the sheet shows and the user can update it.

It stores only a keyed hash of each login (HMAC-SHA256 with a key that stays in the Android Keystore), never the password. If `getPassword` finds nothing saved any more, it forgets them all and asks again next time.

Only save a password that worked. Saving one before the server accepts it leaves a wrong password in the user's password manager.

### Pick a saved one

```dart
await AndroidSignInKit.getPassword(
  usernameController: emailController,
  passwordController: passwordController,
);
```

The picked login is put into your fields. `getPassword` also returns it as a `SavedPassword` (or `null` if the user closed the sheet), so you can leave the controllers out and use `saved.username` and `saved.password` yourself.

The sheet shows the passwords saved for your app. If there are none, it throws `CredentialManagerException` with `noCredential`, so you can hide the button or just do nothing.

`SavedPassword.toString()` leaves the password out, so printing it won't put the password in your logs.

### After picking: log in now, or only fill

When the user picks a saved login, your app decides what happens next, with `onPicked`. The example app lets you try both.

**Log in now.** Picking a saved login usually means "log me in", so skip the extra tap. Pass your login function as `onPicked`; it runs right after the fields are filled:

```dart
Future<void> useSavedPassword() => AndroidSignInKit.getPassword(
  usernameController: emailController,
  passwordController: passwordController,
  onPicked: (_) => logIn(), // your normal login, straight away
);
```

**Only fill.** Leave `onPicked` out. The fields are filled and the user checks them and taps your Log in button:

```dart
Future<void> useSavedPassword() => AndroidSignInKit.getPassword(
  usernameController: emailController,
  passwordController: passwordController,
);
```

To let users choose, pass `onPicked` only when they want it, for example from a setting: `onPicked: logInWhenPicked ? (_) => logIn() : null`.

If the user closes the sheet, nothing is filled and `onPicked` isn't called. `onPicked` gets the `SavedPassword` too, in case you'd rather log in with it than read the fields.

Either way, your `logIn()` can end with `savePassword` as usual. For a login that was picked from the sheet it returns `PasswordSaveResult.unchanged` without showing anything, so there's no need to tell the two cases apart:

```dart
Future<void> logIn() async {
  await myServer.logIn(emailController.text, passwordController.text);
  await AndroidSignInKit.savePassword(
    username: emailController.text,
    password: passwordController.text,
  ); // asks only for a new or changed password
}
```

A good place for the button is a key icon inside the field:

```dart
TextField(
  controller: passwordController,
  obscureText: true,
  decoration: InputDecoration(
    labelText: 'Password',
    suffixIcon: IconButton(
      tooltip: 'Use a saved password',
      icon: const Icon(Icons.key),
      onPressed: useSavedPassword,
    ),
  ),
)
```

## ✍️ Autofill hints

**With this package, leave autofill hints off your login fields on Android.** Flutter only turns autofill on for a field when you set `autofillHints`.

With hints, Android autofill (the older Google Password Manager integration) runs next to Credential Manager. It shows its own "Use your saved password?" sheet as soon as a field is focused, which can appear before or on top of the Credential Manager sheet, and it shows saved logins above the keyboard. Users then see two different-looking sheets for the same thing.

On iOS, web and desktop it's the other way round: autofill hints are how the keychain or the browser fills and saves passwords. So the package has getters that do the right thing on each platform, and you never need a `Platform.isAndroid` check:

| Getter | On Android | Elsewhere |
|---|---|---|
| `AndroidSignInKit.usernameAutofillHints` | `null` (autofill off) | `[AutofillHints.username]` |
| `AndroidSignInKit.passwordAutofillHints` | `null` | `[AutofillHints.password]` |
| `AndroidSignInKit.emailAutofillHints` | `null` | `[AutofillHints.email]` |
| `AndroidSignInKit.newUsernameAutofillHints` | `null` | `[AutofillHints.newUsername]` |
| `AndroidSignInKit.newPasswordAutofillHints` | `null` | `[AutofillHints.newPassword]` |

Use the first two (or `emailAutofillHints` for an email field) on the login screen, and the `new...` ones on a sign-up or change-password screen, where iOS can then suggest a strong password:

```dart
AutofillGroup(
  child: Column(
    children: [
      TextField(
        controller: emailController,
        autofillHints: AndroidSignInKit.usernameAutofillHints,
      ),
      TextField(
        controller: passwordController,
        obscureText: true,
        autofillHints: AndroidSignInKit.passwordAutofillHints,
      ),
    ],
  ),
)
```

Hints that have nothing to do with logins, such as `AutofillHints.name`, `telephoneNumber`, `postalAddress` or `oneTimeCode`, don't compete with Credential Manager. Set those directly as usual.

If you keep login hints on Android anyway, the package still prevents the worst part: `savePassword` ends the autofill session first, so the user gets one "Save password?" prompt, not two.

## 🚪 Signing out

```dart
await AndroidSignInKit.signOut();
```

Call it when the user signs out of your app. It tells Credential Manager to forget the last sign-in, so `autoSelect` and lightweight sign-in won't sign the same account in again without a tap. It doesn't remove saved passwords, granted scopes or Google accounts from the phone.

Clearing that state goes through Google Play services and can take a second. Nothing on screen depends on it, so update your UI first and don't make the user wait:

```dart
setState(() => user = null); // back to the login screen at once
await AndroidSignInKit.signOut();
```

## ⚠️ Errors

Closing a sheet is not an error: `signInWithGoogle`, `getPassword` and `authorize` return `null`, and `savePassword` returns `PasswordSaveResult.declined`.

Everything else throws `CredentialManagerException`:

```dart
try {
  await AndroidSignInKit.signInWithGoogle();
} on CredentialManagerException catch (e) {
  print(e.code);            // CredentialErrorCode.misconfigured
  print(e.message);         // what it means, in plain words
  print(e.platformMessage); // Android's message: "[28444] Developer console is not set up correctly."
  print(e.platformType);    // Android's error type, or the Play services status name
  print(e.statusCode);      // Play services status code, for authorize
}
```

| `code` | When |
|---|---|
| `noCredential` | Nothing to show: no saved passwords, or no (returning) Google account on the phone. |
| `misconfigured` | Google rejected the app: wrong Web client ID, or no Android client with this package name and SHA-1. Also when there's no Web client ID at all. |
| `providerUnavailable` | Google Play services or the credential provider is missing, disabled or out of date. |
| `unsupported` | The device doesn't support Credential Manager. |
| `noProvider` | No password manager on the phone can save passwords. |
| `interrupted` | The request was interrupted, for example by the app going to the background. Try again. |
| `network` | Google couldn't be reached. |
| `invalidToken` | The Google ID token couldn't be read. |
| `unexpectedCredential` | Android returned a different kind of credential than asked for. |
| `noActivity` | The app wasn't in the foreground. |
| `busy` | Another `authorize` call is still waiting for the user. |
| `unknown` | Anything else. Check `platformMessage`. |

`message` is meant for logs. For users, show your own text based on `code`.

### "Developer console is not set up correctly"

This comes back as `misconfigured`. Check that:

- you use the **Web** client ID, not the Android one,
- the Android client's package name matches your `applicationId`,
- its SHA-1 matches the key the app is signed with (debug, release and Play App Signing keys are all different; add each one as its own Android client),
- both clients are in the same Google Cloud project,
- while the app is in testing, your account is a test user.

Changes in Google Cloud Console can take a few minutes to apply.

## 🗝️ Password managers other than Google's

On Android 14 and later, Credential Manager works with every password manager the user turned on in **Settings → Passwords, passkeys and accounts**, such as Samsung Pass, 1Password, Bitwarden or Dashlane, as long as that app supports Credential Manager:

- `getPassword` lists the saved logins from all of them in one sheet.
- `savePassword` saves to the user's preferred one, and the sheet's "Save another way" lets them pick another.

On Android 13 and lower, Credential Manager goes through Google Play services, so only Google Password Manager is used.

## 📦 Release builds

The package ships the R8 rules Credential Manager needs, so minified release builds work without changes.

For apps on Google Play, add the SHA-1 of the **app signing key** as another Android client. You'll find it in Play Console under **Test and release → App integrity**.

## 🍎 iOS and other platforms

Credential Manager only exists on Android, but you don't need `Platform.isAndroid` checks: every method can be called from shared code. On other platforms nothing is shown and you get what a closed sheet would give:

| Method | On iOS, web and desktop |
|---|---|
| `initialize`, `signOut` | Do nothing. |
| `signInWithGoogle`, `attemptLightweightSignIn`, `authorize`, `getPassword` | Return `null`. |
| `savePassword` | Returns `PasswordSaveResult.unsupported`, after letting the iOS keychain or the browser offer to save (see below). |

So the same login code runs everywhere. Use `isSupported` only to hide buttons that would do nothing, such as "Use a saved password":

```dart
if (AndroidSignInKit.isSupported)
  IconButton(icon: const Icon(Icons.key), onPressed: useSavedPassword),
```

On iOS, saving and filling passwords works through autofill hints and the keychain. Use the package's [autofill hint getters](#%EF%B8%8F-autofill-hints) on your fields: they're off on Android and on everywhere else. With them, the `savePassword` you already call after login also makes iOS offer to save the password to the keychain.

## Example

The [example app](https://github.com/parthbhensdadiya226/android_sign_in_kit/tree/main/example) is a login screen with Google Sign-In (sheet, button flow and lightweight), every detail of the signed-in account, Drive access through scopes, password save, and saved password pick (log in directly or just fill the fields). Run it with your Web client ID:

```bash
flutter run --dart-define=WEB_CLIENT_ID=1234-abc.apps.googleusercontent.com
```

## ☕ Support

If this package saves you time, you can support its maintenance with a coffee:

<a href="https://buymeacoffee.com/parthbhensdadiya"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="48"></a>

Or scan the code:

<img src="https://raw.githubusercontent.com/parthbhensdadiya226/android_sign_in_kit/main/doc/support_qr.png" width="160" alt="QR code for buymeacoffee.com/parthbhensdadiya">

## License

MIT
