import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalUrl(String url) async {
  try {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
