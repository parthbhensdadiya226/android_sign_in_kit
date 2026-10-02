/// An OAuth scope: access to one Google API.
///
/// Use the constants, like an enum:
///
/// ```dart
/// scopes: [GoogleScope.driveFile, GoogleScope.calendarReadonly]
/// ```
///
/// Google has hundreds of scopes, so any other one works too:
/// `GoogleScope('https://www.googleapis.com/auth/tasks')`. The full list is
/// at https://developers.google.com/identity/protocols/oauth2/scopes.
///
/// Scopes Google calls sensitive or restricted (marked below) show an
/// "unverified app" warning until Google verifies your app.
final class GoogleScope {
  /// Any scope, by its full URL.
  const GoogleScope(this.value);

  /// The scope's URL (or short name), as Google expects it.
  final String value;

  // Profile

  /// The user's email address. Granted with sign-in.
  static const email = GoogleScope(
    'https://www.googleapis.com/auth/userinfo.email',
  );

  /// The user's public profile: name and photo. Granted with sign-in.
  static const profile = GoogleScope(
    'https://www.googleapis.com/auth/userinfo.profile',
  );

  /// The user's birthday (People API). Sensitive.
  static const birthday = GoogleScope(
    'https://www.googleapis.com/auth/user.birthday.read',
  );

  /// The user's phone numbers (People API). Sensitive.
  static const phoneNumbers = GoogleScope(
    'https://www.googleapis.com/auth/user.phonenumbers.read',
  );

  /// The user's gender (People API). Sensitive.
  static const gender = GoogleScope(
    'https://www.googleapis.com/auth/user.gender.read',
  );

  /// The user's addresses (People API). Sensitive.
  static const addresses = GoogleScope(
    'https://www.googleapis.com/auth/user.addresses.read',
  );

  // Drive

  /// Files your app creates or the user opens with it. Not sensitive, so
  /// usually the best choice.
  static const driveFile = GoogleScope(
    'https://www.googleapis.com/auth/drive.file',
  );

  /// A hidden folder in Drive for your app's own data (backups, settings).
  static const driveAppData = GoogleScope(
    'https://www.googleapis.com/auth/drive.appdata',
  );

  /// Read all of the user's Drive files. Restricted.
  static const driveReadonly = GoogleScope(
    'https://www.googleapis.com/auth/drive.readonly',
  );

  /// Full access to all of the user's Drive files. Restricted.
  static const drive = GoogleScope('https://www.googleapis.com/auth/drive');

  // Docs and Sheets

  /// Read the user's spreadsheets. Sensitive.
  static const spreadsheetsReadonly = GoogleScope(
    'https://www.googleapis.com/auth/spreadsheets.readonly',
  );

  /// Read and edit the user's spreadsheets. Sensitive.
  static const spreadsheets = GoogleScope(
    'https://www.googleapis.com/auth/spreadsheets',
  );

  /// Read the user's documents. Sensitive.
  static const documentsReadonly = GoogleScope(
    'https://www.googleapis.com/auth/documents.readonly',
  );

  /// Read and edit the user's documents. Sensitive.
  static const documents = GoogleScope(
    'https://www.googleapis.com/auth/documents',
  );

  // Calendar

  /// Read the user's calendars and events. Sensitive.
  static const calendarReadonly = GoogleScope(
    'https://www.googleapis.com/auth/calendar.readonly',
  );

  /// Read and edit the user's events. Sensitive.
  static const calendarEvents = GoogleScope(
    'https://www.googleapis.com/auth/calendar.events',
  );

  /// Full access to the user's calendars. Sensitive.
  static const calendar = GoogleScope(
    'https://www.googleapis.com/auth/calendar',
  );

  // Contacts

  /// Read the user's contacts. Sensitive.
  static const contactsReadonly = GoogleScope(
    'https://www.googleapis.com/auth/contacts.readonly',
  );

  /// Read and edit the user's contacts. Sensitive.
  static const contacts = GoogleScope(
    'https://www.googleapis.com/auth/contacts',
  );

  // Gmail

  /// Send email as the user. Sensitive.
  static const gmailSend = GoogleScope(
    'https://www.googleapis.com/auth/gmail.send',
  );

  /// Read the user's email. Restricted.
  static const gmailReadonly = GoogleScope(
    'https://www.googleapis.com/auth/gmail.readonly',
  );

  /// Read, send and organise the user's email. Restricted.
  static const gmailModify = GoogleScope(
    'https://www.googleapis.com/auth/gmail.modify',
  );

  // Tasks

  /// Read the user's tasks. Sensitive.
  static const tasksReadonly = GoogleScope(
    'https://www.googleapis.com/auth/tasks.readonly',
  );

  /// Read and edit the user's tasks. Sensitive.
  static const tasks = GoogleScope('https://www.googleapis.com/auth/tasks');

  // YouTube

  /// Read the user's YouTube account. Sensitive.
  static const youtubeReadonly = GoogleScope(
    'https://www.googleapis.com/auth/youtube.readonly',
  );

  /// Manage the user's YouTube account. Sensitive.
  static const youtube = GoogleScope('https://www.googleapis.com/auth/youtube');

  @override
  bool operator ==(Object other) =>
      other is GoogleScope && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'GoogleScope($value)';
}
