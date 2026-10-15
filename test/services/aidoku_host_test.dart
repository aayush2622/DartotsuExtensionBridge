import 'package:dartotsu_extension_bridge/Services/Aidoku/AidokuDates.dart';
import 'package:dartotsu_extension_bridge/Services/Aidoku/AidokuImages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('swift date formats', () {
    expect(parseAidokuDate('2024-03-05', 'yyyy-MM-dd'), 1709596800);
    expect(parseAidokuDate('March 5, 2024', 'MMMM d, yyyy'), 1709596800);
    expect(parseAidokuDate('Mar 5, 2024', 'MMM d, yyyy'), 1709596800);
    expect(
      parseAidokuDate('2024-03-05T01:00:00+0100', "yyyy-MM-dd'T'HH:mm:ssZ"),
      1709596800,
    );
    expect(
      parseAidokuDate('05/03/2024 12:00 AM', 'dd/MM/yyyy hh:mm a'),
      1709596800,
    );
    expect(
      parseAidokuDate('2024-03-05', 'yyyy-MM-dd', timezone: 'GMT+1'),
      1709593200,
    );
    expect(parseAidokuDate('garbage', 'yyyy-MM-dd'), isNull);
  });

  test('canvas fill and stroke', () {
    final canvas = AidokuCanvas.create(10, 10)!;
    canvas.fillPaths(
      [
        [
          (x: 0.0, y: 0.0),
          (x: 5.0, y: 0.0),
          (x: 5.0, y: 5.0),
          (x: 0.0, y: 5.0),
        ],
      ],
      [1, 0, 0, 1],
    );
    expect(canvas.image.getPixel(2, 2).r, 255);
    expect(canvas.image.getPixel(7, 7).a, 0);
  });
}
