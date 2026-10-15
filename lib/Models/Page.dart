import 'dart:typed_data';

class PageUrl {
  String url;
  Map<String, String>? headers;

  /// Runs on the downloaded image bytes before they are shown or saved, for
  /// sources that scramble or re-encode their pages. Not part of the JSON form.
  Future<Uint8List> Function(Uint8List data)? process;

  PageUrl(this.url, {this.headers, this.process});

  factory PageUrl.fromJson(Map<String, dynamic> json) {
    // See the matching comment in Models/Video.dart: a missing url must not
    // silently become the literal string "null" via null.toString().
    final url = json['url'];
    if (url == null) {
      throw FormatException('PageUrl JSON is missing a "url" field: $json');
    }

    return PageUrl(
      url.toString().trim(),
      headers: (json['headers'] as Map?)?.cast<String, String>(),
    );
  }

  Map<String, dynamic> toJson() => {'url': url, 'headers': headers};
}
