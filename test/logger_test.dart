import 'package:dartotsu_extension_bridge/Logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emoji are dropped from extension logs', () {
    expect(
      stripEmoji('[EXT] 🚀 Initializing StreamPlay optimizations...'),
      '[EXT] Initializing StreamPlay optimizations...',
    );
    expect(
      stripEmoji('[EXT] 📂 Loaded provider stats (0 providers)'),
      '[EXT] Loaded provider stats (0 providers)',
    );
    expect(stripEmoji('[EXT] ✅ Using official TMDB API'), '[EXT] Using official TMDB API');
    expect(stripEmoji('⚠️ Detected Cloudflare protection'), 'Detected Cloudflare protection');
    expect(stripEmoji('[EXT] 📱 Device profile: LOW_END'), '[EXT] Device profile: LOW_END');
  });

  test('plain text and the arrows the logs use stay as they are', () {
    const line = '[EXT] → GET https://x/y (12ms) × timeout … │ ← 200';
    expect(stripEmoji(line), line);
  });
}
