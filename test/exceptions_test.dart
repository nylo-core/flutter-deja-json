import 'package:dejajson/dejajson.dart';
import 'package:test/test.dart';

void main() {
  test('exception toString includes the type and message', () {
    expect(
        const DejaJsonException('base').toString(), 'DejaJsonException: base');
    expect(const DejaJsonFormatException('bad envelope').toString(),
        'DejaJsonFormatException: bad envelope');
    expect(const DejaJsonEncodeException('cannot pack').toString(),
        'DejaJsonEncodeException: cannot pack');
    expect(const DejaJsonUnsupportedException('no zlib here').toString(),
        'DejaJsonUnsupportedException: no zlib here');
  });

  test('every specialised exception is a DejaJsonException', () {
    expect(const DejaJsonFormatException(''), isA<DejaJsonException>());
    expect(const DejaJsonEncodeException(''), isA<DejaJsonException>());
    expect(const DejaJsonUnsupportedException(''), isA<DejaJsonException>());
  });
}
