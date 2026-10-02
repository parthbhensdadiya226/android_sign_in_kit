## 0.1.0

- `initialize`: gets the Google and password sheets ready in the background (Android 14+), so they open on tap instead of after a pause. It also stores the Web client ID and the default sheet options.
- `signInWithGoogle`: Google Sign-In with the account bottom sheet, or Google's "Sign in with Google" button flow. Options for auto-select, previous accounts only, Workspace domain, nonce and scopes.
- `GoogleAccount` has everything Credential Manager returns plus the ID token's claims: Google user ID (`id`), `emailVerified`, `hostedDomain`, `issuedAt`, `expiresAt`, `nonce` and the full `claims` map.
- `attemptLightweightSignIn`: signs a returning user in with as little UI as possible, or returns null without showing anything.
- `authorize`: OAuth scopes through Google's Authorization API, picked with `GoogleScope` constants (or any scope URL), with access token, granted scopes and an optional server auth code.
- The Web client ID is read from `google-services.json` when it isn't passed, for Firebase apps.
- `getPassword`: pick a saved login from the bottom sheet. It can fill your text fields (`usernameController`, `passwordController`) and log in straight away (`onPicked`), or only fill.
- `savePassword`: offers "Save password?" only for a new or changed password, and returns `PasswordSaveResult.saved`, `unchanged` or `declined`. Known logins are remembered across restarts as keyed hashes (HMAC with an Android Keystore key), never as passwords.
- `savePassword` ends any autofill session first, so apps that keep `autofillHints` show one save prompt instead of two.
- `signOut`: clears the Credential Manager sign-in state.
- `CredentialManagerException` with a `CredentialErrorCode`, a plain-words `message`, and Android's `platformMessage`, `platformType` and `statusCode`. A closed sheet returns null (or `declined`) instead of throwing.
- Safe on every platform: off Android the methods do nothing and return null (or `PasswordSaveResult.unsupported`), so shared code needs no platform checks. Autofill hint getters (`usernameAutofillHints`, `passwordAutofillHints`, `emailAutofillHints`, `newUsernameAutofillHints`, `newPasswordAutofillHints`) keep iOS keychain autofill working without competing with Credential Manager on Android.
- R8 rules included for release builds.
