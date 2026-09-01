import 'dart:html' as html;

Future<bool> openExternalUrl(String url) async {
  html.window.open(url, '_blank', 'noopener,noreferrer');
  return true;
}
