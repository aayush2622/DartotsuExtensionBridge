import 'package:dartotsu_extension_bridge/Extensions/ExtensionBridge.dart';
import 'package:dartotsu_extension_bridge/Models/DEpisode.dart';
import 'package:dartotsu_extension_bridge/Extensions/SourceMethods.dart';
import 'package:dartotsu_extension_bridge/Models/Source.dart';
import 'package:dartotsu_extension_bridge/Models/Video.dart';
import 'package:dartotsu_extension_bridge/Services/Aniyomi/AniyomiSourceMethods.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _video(String url) => {
  'url': url,
  'title': url,
  'quality': '1080p',
};

class _FakeBridge implements ExtensionBridge {
  final List<dynamic> events;
  final List<Map<String, dynamic>> sent = [];
  _FakeBridge(this.events);

  @override
  Future<T> call<T>(String method, Map<String, dynamic> args) async {
    sent.add({'method': method, ...args});
    return events.last as T;
  }

  @override
  Stream<dynamic> stream(String method, Map<String, dynamic> args) async* {
    sent.add({'method': method, ...args});
    for (final event in events) {
      yield event;
    }
  }
}

void main() {
  final episode = DEpisode(url: 'ep', name: 'one', episodeNumber: '1');
  final source = Source(id: 's', itemType: ItemType.anime);

  test('getVideoStream yields each batch as it arrives', () async {
    final bridge = _FakeBridge([
      [_video('a'), _video('b')],
      [_video('c')],
    ]);
    final methods = AniyomiSourceMethods(source, bridge);

    final batches = await methods.getVideoStream(episode).toList();

    expect(batches.map((b) => b.map((v) => v.url).toList()).toList(), [
      ['a', 'b'],
      ['c'],
    ]);
    expect(bridge.sent.single['method'], 'getVideoList');
  });

  test('getVideoStream skips malformed videos inside a batch', () async {
    final bridge = _FakeBridge([
      [
        _video('a'),
        {'title': 'no url'},
      ],
    ]);
    final methods = AniyomiSourceMethods(source, bridge);

    final batches = await methods.getVideoStream(episode).toList();

    expect(batches.single.map((v) => v.url).toList(), ['a']);
  });

  test('getVideoList still waits for the complete list', () async {
    final bridge = _FakeBridge([
      [_video('a'), _video('b'), _video('c')],
    ]);
    final methods = AniyomiSourceMethods(source, bridge);

    final list = await methods.getVideoList(episode);

    expect(list.map((v) => v.url).toList(), ['a', 'b', 'c']);
  });

  test('a source without streaming yields its list once', () async {
    final methods = _Waiting();

    final batches = await methods.getVideoStream(episode).toList();

    expect(batches.length, 1);
    expect(batches.single.single.url, 'only');
  });
}

class _Waiting extends SourceMethods {
  @override
  Future<List<Video>> getVideoList(DEpisode episode) async => [
    Video('t', 'only', '720p'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
