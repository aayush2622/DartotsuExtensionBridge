import 'dart:convert';
import 'dart:typed_data';

class PostcardReader {
  PostcardReader(this._data, [this._pos = 0]);

  final Uint8List _data;
  int _pos;

  int get position => _pos;

  int get remaining => _data.length - _pos;

  int readVarU() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = _data[_pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  int readVarI() {
    final z = readVarU();
    return (z & 1) == 0 ? (z >> 1) : -((z + 1) >> 1);
  }

  bool readBool() => _data[_pos++] != 0;

  Uint8List readBytes() {
    final len = readVarU();
    final bytes = _data.sublist(_pos, _pos + len);
    _pos += len;
    return bytes;
  }

  String readString() => utf8.decode(readBytes());

  double readF32() {
    final bd = ByteData.sublistView(_data, _pos, _pos + 4);
    _pos += 4;
    return bd.getFloat32(0, Endian.little);
  }

  double readF64() {
    final bd = ByteData.sublistView(_data, _pos, _pos + 8);
    _pos += 8;
    return bd.getFloat64(0, Endian.little);
  }

  bool readOptionTag() => readBool();

  T? readOption<T>(T Function() reader) => readOptionTag() ? reader() : null;

  List<T> readVec<T>(T Function() reader) {
    final len = readVarU();
    return List.generate(len, (_) => reader());
  }

  Map<String, String> readStringMap() {
    final len = readVarU();
    final map = <String, String>{};
    for (var i = 0; i < len; i++) {
      map[readString()] = readString();
    }
    return map;
  }

  void skip(int bytes) => _pos += bytes;
}

class PostcardWriter {
  final BytesBuilder _builder = BytesBuilder();

  void writeVarU(int n) {
    while (true) {
      final byte = n & 0x7f;
      n >>= 7;
      if (n != 0) {
        _builder.addByte(byte | 0x80);
      } else {
        _builder.addByte(byte);
        break;
      }
    }
  }

  void writeVarI(int n) {
    final z = n >= 0 ? (n << 1) : (((-n) << 1) - 1);
    writeVarU(z);
  }

  void writeBool(bool b) => _builder.addByte(b ? 1 : 0);

  void writeBytes(List<int> bytes) {
    writeVarU(bytes.length);
    _builder.add(bytes);
  }

  void writeString(String s) => writeBytes(utf8.encode(s));

  void writeF32(double d) {
    final bd = ByteData(4)..setFloat32(0, d, Endian.little);
    _builder.add(bd.buffer.asUint8List());
  }

  void writeOption<T>(T? value, void Function(T) writer) {
    if (value == null) {
      writeBool(false);
    } else {
      writeBool(true);
      writer(value);
    }
  }

  void writeVec<T>(List<T> items, void Function(T) writer) {
    writeVarU(items.length);
    for (final item in items) {
      writer(item);
    }
  }

  Uint8List takeBytes() => _builder.takeBytes();
}
