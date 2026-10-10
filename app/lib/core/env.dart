/// Set at build time:
///   flutter run --dart-define=API_BASE_URL=http://localhost:3000
/// The default is the deployed service, so a judge opening the hosted build
/// needs no flags.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://sorted-api-a4zo.onrender.com',
);
