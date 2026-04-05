import 'package:comerune/data/follow/follow_program.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProgramStatus', () {
    test('parseProgramStatus parses known status strings', () {
      expect(parseProgramStatus('reserved'), ProgramStatus.reserved);
      expect(parseProgramStatus('test'), ProgramStatus.test);
      expect(parseProgramStatus('on_air'), ProgramStatus.onAir);
      expect(parseProgramStatus('onAir'), ProgramStatus.onAir);
      expect(parseProgramStatus('end'), ProgramStatus.ended);
      expect(parseProgramStatus('ended'), ProgramStatus.ended);
    });

    test('parseProgramStatus returns null for unknown values', () {
      expect(parseProgramStatus('unknown'), isNull);
      expect(parseProgramStatus(null), isNull);
      expect(parseProgramStatus(''), isNull);
    });
  });

  group('FollowProgram broadcast control', () {
    test('canStart is true for reserved status', () {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.reserved,
      );
      expect(program.canStart, isTrue);
      expect(program.canEnd, isFalse);
    });

    test('canStart is true for test status', () {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.test,
      );
      expect(program.canStart, isTrue);
      expect(program.canEnd, isFalse);
    });

    test('canEnd is true for onAir status', () {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.onAir,
      );
      expect(program.canStart, isFalse);
      expect(program.canEnd, isTrue);
    });

    test('neither canStart nor canEnd for ended status', () {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.ended,
      );
      expect(program.canStart, isFalse);
      expect(program.canEnd, isFalse);
    });

    test('neither canStart nor canEnd when status is null', () {
      final FollowProgram program = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
      );
      expect(program.canStart, isFalse);
      expect(program.canEnd, isFalse);
    });
  });

  group('FollowProgram.copyWith', () {
    test('copies with new status', () {
      final FollowProgram original = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.reserved,
      );

      final FollowProgram updated =
          original.copyWith(status: ProgramStatus.onAir);

      expect(updated.programId, 'lv123');
      expect(updated.title, 'Test');
      expect(updated.status, ProgramStatus.onAir);
    });

    test('copies with new endAt', () {
      final DateTime endAt = DateTime(2026, 4, 1, 12, 0);
      final FollowProgram original = FollowProgram(
        programId: 'lv123',
        title: 'Test',
        providerName: 'User',
        status: ProgramStatus.onAir,
      );

      final FollowProgram updated = original.copyWith(endAt: endAt);

      expect(updated.endAt, endAt);
      expect(updated.status, ProgramStatus.onAir);
    });
  });
}
