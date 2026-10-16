import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where motion is allowed to be defined rather than merely used.
const _motionDirectory = 'lib/core/motion';

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// Every `file:line` under lib/ outside the motion directory where [pattern]
/// matches, with the offending line, so a failure says what to fix.
List<String> _offences(RegExp pattern) {
  final out = <String>[];
  for (final file in _dartFiles('lib')) {
    if (file.path.startsWith(_motionDirectory)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (pattern.hasMatch(lines[i])) {
        out.add('${file.path}:${i + 1}  ${lines[i].trim()}');
      }
    }
  }
  return out;
}

void main() {
  group('motion stays in the motion directory', () {
    test('no screen invents its own timing', () {
      // A duration or delay passed as a literal is a timing decided in
      // whatever file happened to need it. The point of the tokens is that
      // the app has a tempo rather than forty of them, and that changing it
      // is one edit. A named token in lib/core/motion is the way to add one.
      final offences = _offences(RegExp(
        r'(duration|delay|reverseDuration|transitionDuration):\s*'
        r'(const\s+)?(Duration\(|[0-9]+\.ms)',
      ));
      expect(
        offences,
        isEmpty,
        reason: 'Use a SortedDurations token instead:\n${offences.join('\n')}',
      );
    });

    test('no screen invents its own curve', () {
      // Curves.* is the giveaway. Arrivals get a spring from SortedSprings;
      // the two cases where a spring is wrong are SortedCurves.exit and
      // SortedCurves.loop, and there is not a third.
      final offences = _offences(RegExp(r'\bCurves\.'));
      expect(
        offences,
        isEmpty,
        reason: 'Use a SortedSprings or SortedCurves token instead:\n'
            '${offences.join('\n')}',
      );
    });
  });

  group('the bouncy spring stays rationed', () {
    test('it is used exactly twice: the stamp, and payment landing', () {
      // Rule 2 of the motion direction. Overshoot everywhere is how springy
      // becomes childish, so the budget is two and this test is the budget.
      // If a third use is genuinely right, the rule is what changes — here,
      // deliberately — not quietly at the call site.
      final uses = <String>[];
      for (final file in _dartFiles('lib')) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].contains('SortedSprings.bouncy') &&
              !lines[i].trimLeft().startsWith('///')) {
            uses.add('${file.path}:${i + 1}');
          }
        }
      }

      expect(uses, hasLength(2), reason: 'bouncy is used at:\n${uses.join('\n')}');
      expect(
        uses.map((u) => u.split(':').first),
        containsAll(<String>[
          'lib/widgets/sorted_stamp.dart',
          'lib/core/motion/paid_pop.dart',
        ]),
      );
    });
  });

  group('web runs the same motion as everything else', () {
    test('the motion layer never asks what platform it is on', () {
      // The old page transitions bailed out to a flat cross-fade behind
      // `if (kIsWeb)`, which made the hosted build — the one judges open —
      // the only build in the project with no motion in it. Degrade a named
      // effect if it is measured to cost frames; never the whole platform.
      //
      // Scoped to the motion layer on purpose. Elsewhere kIsWeb is answering
      // real questions — there is no camera and no share intent on the web —
      // and those are capabilities, not animations.
      final offences = <String>[];
      for (final file in _dartFiles(_motionDirectory)) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('kIsWeb') && !line.trimLeft().startsWith('///')) {
            offences.add('${file.path}:${i + 1}  ${line.trim()}');
          }
        }
      }
      expect(offences, isEmpty, reason: offences.join('\n'));
    });
  });
}
