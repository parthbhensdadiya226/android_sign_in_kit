import 'package:android_sign_in_kit/android_sign_in_kit.dart';
import 'package:flutter/material.dart';

/// The Web client ID from Google Cloud Console. Pass yours with
/// `flutter run --dart-define=WEB_CLIENT_ID=1234-abc.apps.googleusercontent.com`,
/// or leave it out if the app has google-services.json.
const webClientId = String.fromEnvironment('WEB_CLIENT_ID');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Get the sheets ready now, so they open instantly on the first tap.
  AndroidSignInKit.initialize(
    serverClientId: webClientId.isEmpty ? null : webClientId,
  );
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android Sign-In Kit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  /// Who is signed in: a Google account or a username. Null when signed out.
  GoogleAccount? _google;
  String? _user;

  /// What picking a saved password does: log in right away, or only fill
  /// the fields and wait for "Log in".
  bool _logInWhenPicked = true;

  bool _showPassword = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a call and shows its error, with the type and Android's message.
  Future<void> _run(Future<void> Function() call) async {
    try {
      await call();
    } on CredentialManagerException catch (e) {
      _say(
        '${e.code.name}: ${e.message}'
        '${e.platformMessage == null ? '' : '\n\n${e.platformMessage}'}',
      );
    }
  }

  Future<void> _signInWithGoogle({bool button = false}) => _run(() async {
    // No serverClientId needed: initialize() got it.
    final account = await AndroidSignInKit.signInWithGoogle(
      useButtonFlow: button,
    );
    if (account == null) return; // the user closed the sheet
    setState(() => _google = account);
  });

  Future<void> _lightweightSignIn() => _run(() async {
    final account = await AndroidSignInKit.attemptLightweightSignIn();
    if (account == null) {
      _say('No returning Google account. Use "Continue with Google".');
      return;
    }
    setState(() => _google = account);
  });

  Future<void> _grantDrive() => _run(() async {
    final google = _google!;
    final authorization = await AndroidSignInKit.authorize(
      scopes: [GoogleScope.driveFile],
      accountEmail: google.email,
    );
    if (authorization == null) return; // the user declined
    setState(() => _google = google.withAuthorization(authorization));
  });

  // Fills both fields; with "Log in now" selected, also logs in.
  Future<void> _fillSaved() => _run(() async {
    await AndroidSignInKit.getPassword(
      usernameController: _username,
      passwordController: _password,
      onPicked: _logInWhenPicked ? (_) => _logIn() : null,
    );
  });

  Future<void> _logIn() => _run(() async {
    final username = _username.text.trim();
    if (username.isEmpty || _password.text.isEmpty) {
      _say('Enter a username and password.');
      return;
    }
    // Your real login call goes here. Offer to save only after it succeeds.
    setState(() => _user = username);
    // Shows "Save password?" only for a new or changed password.
    final result = await AndroidSignInKit.savePassword(
      username: username,
      password: _password.text,
    );
    if (result == PasswordSaveResult.saved) _say('Password saved.');
  });

  Future<void> _signOut() => _run(() async {
    // Update the screen first: clearing the sign-in state goes through
    // Google Play services and can take a moment, and nothing has to wait
    // for it.
    _password.clear();
    setState(() {
      _google = null;
      _user = null;
    });
    await AndroidSignInKit.signOut();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Android Sign-In Kit')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: _google != null || _user != null
              ? _signedIn(context)
              : _signedOut(context),
        ),
      ),
    );
  }

  List<Widget> _signedIn(BuildContext context) {
    final google = _google;
    final theme = Theme.of(context);
    return [
      CircleAvatar(
        radius: 40,
        foregroundImage: google?.photoUrl == null
            ? null
            : NetworkImage(google!.photoUrl!),
        child: const Icon(Icons.person, size: 40),
      ),
      const SizedBox(height: 16),
      Text(
        google?.displayName ?? _user!,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(
        google != null ? 'Signed in with Google' : 'Signed in with a password',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      ),
      if (google != null) ..._googleDetails(google),
      const SizedBox(height: 24),
      OutlinedButton(onPressed: _signOut, child: const Text('Sign out')),
    ];
  }

  List<Widget> _googleDetails(GoogleAccount google) {
    final authorization = google.authorization;
    String? short(String? token) =>
        token == null ? null : '${token.substring(0, 12)}…';
    final rows = {
      'Email': google.email,
      'Email verified': google.emailVerified?.toString(),
      'Given name': google.givenName,
      'Family name': google.familyName,
      'Google user ID': google.id,
      'Workspace domain': google.hostedDomain ?? 'none (personal account)',
      'Phone number': google.phoneNumber,
      'ID token': short(google.idToken),
      'Token expires': google.expiresAt?.toLocal().toString().split('.')[0],
      if (authorization != null) ...{
        'Granted scopes': authorization.grantedScopes.join('\n'),
        'Access token': short(authorization.accessToken),
      },
    };
    return [
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            for (final MapEntry(:key, :value) in rows.entries)
              if (value != null)
                ListTile(dense: true, title: Text(key), subtitle: Text(value)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (authorization == null)
        FilledButton.tonalIcon(
          onPressed: _grantDrive,
          icon: const Icon(Icons.add_to_drive),
          label: const Text('Allow Google Drive access'),
        ),
    ];
  }

  List<Widget> _signedOut(BuildContext context) {
    return [
      FilledButton.icon(
        onPressed: _signInWithGoogle,
        icon: const Icon(Icons.account_circle),
        label: const Text('Continue with Google'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => _signInWithGoogle(button: true),
        child: const Text('Sign in with Google (button flow)'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _lightweightSignIn,
        child: const Text('Lightweight sign-in (returning user)'),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('or'),
            ),
            Expanded(child: Divider()),
          ],
        ),
      ),
      TextField(
        controller: _username,
        keyboardType: TextInputType.emailAddress,
        // No hints on Android (they'd bring up autofill next to the
        // Credential Manager sheets); the usual ones on other platforms.
        autofillHints: AndroidSignInKit.usernameAutofillHints,
        decoration: InputDecoration(
          labelText: 'Email or username',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.alternate_email),
          // Opens the saved passwords sheet.
          suffixIcon: IconButton(
            tooltip: 'Use a saved password',
            icon: const Icon(Icons.key),
            onPressed: _fillSaved,
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: !_showPassword,
        autofillHints: AndroidSignInKit.passwordAutofillHints,
        decoration: InputDecoration(
          labelText: 'Password',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Use a saved password',
                icon: const Icon(Icons.key),
                onPressed: _fillSaved,
              ),
              IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'After picking a saved password',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: true,
            icon: Icon(Icons.login),
            label: Text('Log in now'),
          ),
          ButtonSegment(
            value: false,
            icon: Icon(Icons.edit_note),
            label: Text('Only fill'),
          ),
        ],
        selected: {_logInWhenPicked},
        onSelectionChanged: (value) =>
            setState(() => _logInWhenPicked = value.single),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _logIn, child: const Text('Log in')),
    ];
  }
}
