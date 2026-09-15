import 'package:dartotsu_extension_bridge/NetworkClient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cookieHeaderFromStoredCookies', () {
    test('builds a Cookie header from a StoredCookieDto-shaped JSON array', () {
      const json =
          '[{"name":"session","value":"abc","domain":"x.com","hostOnly":true,'
          '"path":"/","expires":null,"secure":true,"httpOnly":true},'
          '{"name":"theme","value":"dark","domain":"x.com","hostOnly":true,'
          '"path":"/","expires":null,"secure":false,"httpOnly":false}]';

      expect(cookieHeaderFromStoredCookies(json), 'session=abc; theme=dark');
    });

    test('returns null for an empty array', () {
      expect(cookieHeaderFromStoredCookies('[]'), isNull);
    });

    test('returns null for null/empty/malformed input', () {
      expect(cookieHeaderFromStoredCookies(null), isNull);
      expect(cookieHeaderFromStoredCookies(''), isNull);
      expect(cookieHeaderFromStoredCookies('not json'), isNull);
      expect(cookieHeaderFromStoredCookies('{"not":"a list"}'), isNull);
    });

    test('skips malformed entries but keeps valid ones', () {
      const json = '[{"name":"a","value":"1"},{"missing":"fields"},"junk"]';
      expect(cookieHeaderFromStoredCookies(json), 'a=1');
    });
  });

  group('splitSetCookieHeader', () {
    test('returns a single cookie untouched', () {
      expect(splitSetCookieHeader('session=abc; Path=/'), [
        'session=abc; Path=/',
      ]);
    });

    test('splits two cookies joined by package:http\'s comma flattening', () {
      expect(splitSetCookieHeader('a=1; Path=/,b=2; Path=/'), [
        'a=1; Path=/',
        'b=2; Path=/',
      ]);
    });

    test('does not split on the comma inside an Expires date', () {
      final header =
          'session=abc; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Path=/';
      expect(splitSetCookieHeader(header), [header]);
    });

    test('keeps Expires commas intact across multiple joined cookies', () {
      final header =
          'a=1; Expires=Wed, 09 Jun 2021 10:18:14 GMT,b=2; Expires=Thu, 10 Jun 2021 10:18:14 GMT';
      expect(splitSetCookieHeader(header), [
        'a=1; Expires=Wed, 09 Jun 2021 10:18:14 GMT',
        'b=2; Expires=Thu, 10 Jun 2021 10:18:14 GMT',
      ]);
    });
  });
}
