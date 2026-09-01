export 'external_url_opener_stub.dart'
    if (dart.library.html) 'external_url_opener_web.dart'
    if (dart.library.io) 'external_url_opener_io.dart';
