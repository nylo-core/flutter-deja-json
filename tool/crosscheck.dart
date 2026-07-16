// Maintainer tool: validates this package against vectors produced by the
// nylo/dejajson Laravel package (or any other DejaJson implementation).
//
//   dart run tool/crosscheck.dart <vectors.json> <report.json>
//
// For every vector it checks that the PHP-encoded envelopes (both modes)
// decode to the exact original data, re-encodes the data itself, and emits
// Dart-encoded envelopes for the other side to verify the reverse direction:
//
//   php bin/generate-vectors.php --merge <report.json>
import 'dart:convert';
import 'dart:io';

import 'package:dejajson/dejajson.dart';

import '../test/helpers.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
        'usage: dart run tool/crosscheck.dart <vectors.json> <report.json>');
    exitCode = 64;
    return;
  }

  final fixture =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  const codec = DejaJsonCodec();

  final dictionaryMeta = fixture['dictionary'] as Map<String, dynamic>;
  final dictionary = DejaJsonDictionary.fromBytes(
      base64.decode(dictionaryMeta['base64'] as String));

  var failures = 0;

  if (dictionary.id != dictionaryMeta['id']) {
    stderr.writeln('dictionary id mismatch: computed ${dictionary.id}, '
        'fixture says ${dictionaryMeta['id']}');
    failures++;
  }

  final results = <Map<String, Object?>>[];
  final dartEnvelopes = <Map<String, Object?>>[];

  for (final v in (fixture['vectors'] as List).cast<Map<String, dynamic>>()) {
    final name = v['name'] as String;
    final Object? data = v['data'];

    var zOk = false;
    var dOk = false;
    var selfOk = false;

    try {
      zOk = deepEquals(codec.decode(base64.decode(v['z'] as String)), data);
    } on Object catch (e) {
      stderr.writeln('mode z decode threw for "$name": $e');
    }

    try {
      dOk = deepEquals(
          codec.decode(base64.decode(v['d'] as String), dictionary: dictionary),
          data);
    } on Object catch (e) {
      stderr.writeln('mode d decode threw for "$name": $e');
    }

    final dartZ = codec.encode(data, modes: 'z');
    final dartD = codec.encode(data, modes: 'd', dictionary: dictionary);

    try {
      selfOk = deepEquals(codec.decode(dartZ), data) &&
          deepEquals(codec.decode(dartD, dictionary: dictionary), data);
    } on Object catch (e) {
      stderr.writeln('self round trip threw for "$name": $e');
    }

    if (!zOk || !dOk || !selfOk) failures++;
    results.add({'name': name, 'zOk': zOk, 'dOk': dOk, 'selfOk': selfOk});
    dartEnvelopes.add({
      'name': name,
      'z': base64.encode(dartZ),
      'd': base64.encode(dartD),
    });
  }

  File(args[1]).writeAsStringSync(jsonEncode({
    'failures': failures,
    'results': results,
    'dartEnvelopes': dartEnvelopes,
  }));

  stdout.writeln(
      'vectors: ${results.length}, failures: $failures — dart envelopes '
      'written for the reverse check');
  exitCode = failures == 0 ? 0 : 1;
}
