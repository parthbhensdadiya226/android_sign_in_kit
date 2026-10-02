import 'package:android_sign_in_kit/android_sign_in_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('android_sign_in_kit');
  final calls = <MethodCall>[];
  final textInputCalls = <MethodCall>[];

  /// Answers every call with [answer], or throws it if it's an exception.
  void reply(Object? answer) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (answer is Exception) throw answer;
          return answer;
        });
  }

  /// Answers each method with its entry in [answers].
  void replyTo(Map<String, Object?> answers) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final answer = answers[call.method];
          if (answer is Exception) throw answer;
          return answer;
        });
  }

  setUp(() {
    calls.clear();
    textInputCalls.clear();
    AndroidSignInKit.resetForTesting();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          textInputCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('initialize', () {
    test('sends the settings', () async {
      reply(null);
      await AndroidSignInKit.initialize(
        serverClientId: 'web-id',
        autoSelect: true,
      );
      expect(calls.single.method, 'initialize');
      expect(calls.single.arguments, {
        'serverClientId': 'web-id',
        'autoSelect': true,
        'onlyPreviousAccounts': false,
      });
    });

    test('signInWithGoogle then uses its settings', () async {
      reply(null);
      await AndroidSignInKit.initialize(
        serverClientId: 'web-id',
        autoSelect: true,
      );
      await AndroidSignInKit.signInWithGoogle();
      expect(calls.last.arguments, {
        'serverClientId': 'web-id',
        'autoSelect': true,
        'onlyPreviousAccounts': false,
        'useButtonFlow': false,
        'hostedDomain': null,
        'nonce': null,
      });
      // Arguments still win over the initialize() settings.
      await AndroidSignInKit.signInWithGoogle(
        serverClientId: 'other',
        autoSelect: false,
      );
      expect(calls.last.arguments['serverClientId'], 'other');
      expect(calls.last.arguments['autoSelect'], false);
    });

    test(
      'without a client ID, Android falls back to google-services.json',
      () async {
        reply(null);
        await AndroidSignInKit.signInWithGoogle();
        expect(calls.single.arguments['serverClientId'], isNull);
      },
    );
  });

  group('signInWithGoogle', () {
    test('sends the options and reads the account', () async {
      reply({
        'email': 'parth@example.com',
        'idToken': 'jwt',
        'displayName': 'Parth B',
        'givenName': 'Parth',
        'familyName': 'B',
        'photoUrl': 'https://example.com/p.png',
        'phoneNumber': null,
      });
      final account = await AndroidSignInKit.signInWithGoogle(
        serverClientId: 'web-id',
        autoSelect: true,
        nonce: 'n',
      );
      expect(calls.single.method, 'signInWithGoogle');
      expect(calls.single.arguments, {
        'serverClientId': 'web-id',
        'autoSelect': true,
        'onlyPreviousAccounts': false,
        'useButtonFlow': false,
        'hostedDomain': null,
        'nonce': 'n',
      });
      expect(account!.email, 'parth@example.com');
      expect(account.idToken, 'jwt');
      expect(account.displayName, 'Parth B');
      expect(account.photoUrl, 'https://example.com/p.png');
      expect(account.phoneNumber, isNull);
    });

    test('returns null when the sheet is closed', () async {
      reply(null);
      expect(
        await AndroidSignInKit.signInWithGoogle(serverClientId: 'x'),
        isNull,
      );
    });

    test('maps a setup error, with the platform details', () async {
      reply(
        PlatformException(
          code: 'misconfigured',
          message: '[28444] Developer console is not set up correctly.',
          details: {'type': 'TYPE_UNKNOWN', 'statusCode': null},
        ),
      );
      await expectLater(
        AndroidSignInKit.signInWithGoogle(serverClientId: 'x'),
        throwsA(
          isA<CredentialManagerException>()
              .having((e) => e.code, 'code', CredentialErrorCode.misconfigured)
              .having(
                (e) => e.message,
                'message',
                CredentialErrorCode.misconfigured.description,
              )
              .having(
                (e) => e.platformMessage,
                'platformMessage',
                contains('28444'),
              )
              .having((e) => e.platformType, 'platformType', 'TYPE_UNKNOWN'),
        ),
      );
    });

    test('reads the claims from the ID token', () async {
      reply({
        'email': 'parth@example.com',
        'idToken':
            'header.eyJzdWIiOiAiMTIzNDU2Nzg5MCIsICJlbWFpbF92ZXJpZmllZCI6IHRydWUsICJoZCI6ICJleGFtcGxlLmNvbSIsICJpYXQiOiAxNzkwMDAwMDAwLCAiZXhwIjogMTc5MDAwMzYwMCwgIm5vbmNlIjogIm4ifQ.signature',
      });
      final account = await AndroidSignInKit.signInWithGoogle(
        serverClientId: 'x',
      );
      expect(account!.id, '1234567890');
      expect(account.emailVerified, isTrue);
      expect(account.hostedDomain, 'example.com');
      expect(account.nonce, 'n');
      expect(account.issuedAt, DateTime.utc(2026, 9, 21, 14, 13, 20));
      expect(
        account.expiresAt!.difference(account.issuedAt!),
        const Duration(hours: 1),
      );
    });

    test('a token that is not a JWT gives empty claims', () async {
      reply({'email': 'parth@example.com', 'idToken': 'not-a-jwt'});
      final account = await AndroidSignInKit.signInWithGoogle(
        serverClientId: 'x',
      );
      expect(account!.claims, isEmpty);
      expect(account.id, isNull);
    });

    test('with scopes, asks for them for the signed-in account', () async {
      replyTo({
        'signInWithGoogle': {'email': 'parth@example.com', 'idToken': 'jwt'},
        'authorize': {
          'accessToken': 'ya29.token',
          'grantedScopes': [GoogleScope.driveFile.value],
          'serverAuthCode': null,
          'email': 'parth@example.com',
        },
      });
      final account = await AndroidSignInKit.signInWithGoogle(
        serverClientId: 'web-id',
        scopes: [GoogleScope.driveFile],
      );
      expect(calls.map((c) => c.method), ['signInWithGoogle', 'authorize']);
      expect(calls.last.arguments['accountEmail'], 'parth@example.com');
      expect(calls.last.arguments['scopes'], [GoogleScope.driveFile.value]);
      expect(account!.authorization!.accessToken, 'ya29.token');
      expect(account.authorization!.hasScope(GoogleScope.driveFile), isTrue);
      expect(account.authorization.toString(), isNot(contains('ya29')));
    });

    test('declined scopes still return the account', () async {
      replyTo({
        'signInWithGoogle': {'email': 'parth@example.com', 'idToken': 'jwt'},
        'authorize': null,
      });
      final account = await AndroidSignInKit.signInWithGoogle(
        serverClientId: 'web-id',
        scopes: [GoogleScope.driveFile],
      );
      expect(account!.email, 'parth@example.com');
      expect(account.authorization, isNull);
    });
  });

  group('attemptLightweightSignIn', () {
    test('only offers returning accounts, signing in without a tap', () async {
      reply({'email': 'parth@example.com', 'idToken': 'jwt'});
      final account = await AndroidSignInKit.attemptLightweightSignIn(
        serverClientId: 'web-id',
      );
      expect(account!.email, 'parth@example.com');
      expect(calls.single.arguments['autoSelect'], isTrue);
      expect(calls.single.arguments['onlyPreviousAccounts'], isTrue);
    });

    test('returns null when there is no returning account', () async {
      reply(PlatformException(code: 'noCredential'));
      expect(
        await AndroidSignInKit.attemptLightweightSignIn(
          serverClientId: 'web-id',
        ),
        isNull,
      );
    });

    test('other errors are still thrown', () async {
      reply(PlatformException(code: 'misconfigured'));
      await expectLater(
        AndroidSignInKit.attemptLightweightSignIn(
          serverClientId: 'web-id',
        ),
        throwsA(isA<CredentialManagerException>()),
      );
    });
  });

  group('authorize', () {
    test('sends the request and reads the result', () async {
      reply({
        'accessToken': 'ya29.token',
        'grantedScopes': ['email', 'https://example.com/custom'],
        'serverAuthCode': '4/code',
        'email': 'parth@example.com',
      });
      final authorization = await AndroidSignInKit.authorize(
        scopes: [
          GoogleScope.email,
          const GoogleScope('https://example.com/custom'),
        ],
        accountEmail: 'parth@example.com',
        offlineAccess: true,
        serverClientId: 'web-id',
      );
      expect(calls.single.arguments, {
        'scopes': [GoogleScope.email.value, 'https://example.com/custom'],
        'accountEmail': 'parth@example.com',
        'hostedDomain': null,
        'offlineAccess': true,
        'forceRefreshToken': false,
        'serverClientId': 'web-id',
      });
      // Short names from Google match the constants.
      expect(authorization!.hasScope(GoogleScope.email), isTrue);
      expect(
        authorization.hasScope(const GoogleScope('https://example.com/custom')),
        isTrue,
      );
      expect(authorization.hasScope(GoogleScope.drive), isFalse);
      expect(authorization.serverAuthCode, '4/code');
      expect(authorization.email, 'parth@example.com');
    });

    test('returns null when the user declines', () async {
      reply(null);
      expect(
        await AndroidSignInKit.authorize(scopes: [GoogleScope.email]),
        isNull,
      );
    });

    test('passes on the Play services status code', () async {
      reply(
        PlatformException(
          code: 'network',
          message: '7: ',
          details: {'type': 'NETWORK_ERROR', 'statusCode': 7},
        ),
      );
      await expectLater(
        AndroidSignInKit.authorize(scopes: [GoogleScope.email]),
        throwsA(
          isA<CredentialManagerException>()
              .having((e) => e.code, 'code', CredentialErrorCode.network)
              .having((e) => e.statusCode, 'statusCode', 7)
              .having((e) => e.platformType, 'platformType', 'NETWORK_ERROR'),
        ),
      );
    });
  });

  group('passwords', () {
    test('savePassword sends the login and reads the result', () async {
      for (final result in PasswordSaveResult.values) {
        reply(result.name);
        expect(
          await AndroidSignInKit.savePassword(
            username: 'parth',
            password: 'secret',
          ),
          result,
        );
      }
      expect(calls.last.method, 'savePassword');
      expect(calls.last.arguments, {'username': 'parth', 'password': 'secret'});
    });

    test('savePassword ends the autofill session without saving', () async {
      reply('saved');
      await AndroidSignInKit.savePassword(username: 'a', password: 'b');
      expect(textInputCalls.single.method, 'TextInput.finishAutofillContext');
      expect(textInputCalls.single.arguments, isFalse);
    });

    test('getPassword reads the picked password', () async {
      reply({'username': 'parth', 'password': 'secret'});
      final saved = await AndroidSignInKit.getPassword();
      expect(saved!.username, 'parth');
      expect(saved.password, 'secret');
      expect(saved.toString(), isNot(contains('secret')));
    });

    test('getPassword fills the fields, then calls onPicked', () async {
      reply({'username': 'parth', 'password': 'secret'});
      final username = TextEditingController();
      final password = TextEditingController();
      String? filledWhenPicked;
      final saved = await AndroidSignInKit.getPassword(
        usernameController: username,
        passwordController: password,
        onPicked: (saved) async => filledWhenPicked = password.text,
      );
      expect(username.text, 'parth');
      expect(password.text, 'secret');
      expect(filledWhenPicked, 'secret');
      expect(saved!.username, 'parth');
    });

    test(
      'getPassword fills and calls nothing when the sheet is closed',
      () async {
        reply(null);
        final username = TextEditingController(text: 'typed');
        var picked = false;
        final saved = await AndroidSignInKit.getPassword(
          usernameController: username,
          onPicked: (_) => picked = true,
        );
        expect(saved, isNull);
        expect(username.text, 'typed');
        expect(picked, isFalse);
      },
    );

    test('getPassword throws noCredential when nothing is saved', () async {
      reply(PlatformException(code: 'noCredential'));
      await expectLater(
        AndroidSignInKit.getPassword(),
        throwsA(
          isA<CredentialManagerException>().having(
            (e) => e.code,
            'code',
            CredentialErrorCode.noCredential,
          ),
        ),
      );
    });
  });

  test('signOut calls the platform', () async {
    reply(null);
    await AndroidSignInKit.signOut();
    expect(calls.single.method, 'signOut');
  });

  test('unknown error codes become unknown', () async {
    reply(PlatformException(code: 'somethingNew'));
    await expectLater(
      AndroidSignInKit.signOut(),
      throwsA(
        isA<CredentialManagerException>().having(
          (e) => e.code,
          'code',
          CredentialErrorCode.unknown,
        ),
      ),
    );
  });

  test('autofill hints are off on Android and on elsewhere', () {
    List<List<String>?> hints() => [
      AndroidSignInKit.usernameAutofillHints,
      AndroidSignInKit.passwordAutofillHints,
      AndroidSignInKit.emailAutofillHints,
      AndroidSignInKit.newUsernameAutofillHints,
      AndroidSignInKit.newPasswordAutofillHints,
    ];
    expect(hints(), everyElement(isNull));
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(hints(), [
      [AutofillHints.username],
      [AutofillHints.password],
      [AutofillHints.email],
      [AutofillHints.newUsername],
      [AutofillHints.newPassword],
    ]);
  });

  test('off Android every method is safe and shows nothing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(AndroidSignInKit.isSupported, isFalse);

    await AndroidSignInKit.initialize(serverClientId: 'web-id');
    expect(await AndroidSignInKit.signInWithGoogle(), isNull);
    expect(await AndroidSignInKit.attemptLightweightSignIn(), isNull);
    expect(
      await AndroidSignInKit.authorize(scopes: [GoogleScope.email]),
      isNull,
    );
    expect(await AndroidSignInKit.getPassword(), isNull);
    await AndroidSignInKit.signOut();
    expect(calls, isEmpty);

    // Lets the iOS keychain offer to save, if the fields have autofill hints.
    expect(
      await AndroidSignInKit.savePassword(username: 'a', password: 'b'),
      PasswordSaveResult.unsupported,
    );
    expect(textInputCalls.single.method, 'TextInput.finishAutofillContext');
    expect(textInputCalls.single.arguments, isTrue);
    expect(calls, isEmpty);
  });
}
