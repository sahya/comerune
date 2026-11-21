import 'package:comerune/data/connection/comment_post_time_budget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommentPostTimeBudget (Issue #1029)', () {
    test('step bounds add up to no more than the total budget', () {
      expect(
        CommentPostTimeBudget.stepsTotal,
        lessThanOrEqualTo(CommentPostTimeBudget.total),
      );
    });

    test('total budget is at most 30 seconds', () {
      expect(
        CommentPostTimeBudget.total,
        lessThanOrEqualTo(const Duration(seconds: 30)),
      );
    });

    test('WebSocket connect bound is at least 10 seconds', () {
      expect(
        CommentPostTimeBudget.connect,
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
    });
  });
}
