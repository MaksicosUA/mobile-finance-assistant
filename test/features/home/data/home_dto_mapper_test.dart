import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/home/data/home_dto.dart';
import 'package:mobile_finance_assistant/features/home/data/home_mapper.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';
import 'package:mobile_finance_assistant/features/home/data/mock_home_repository.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';

import '../../../support/home_contract_fixture.dart';

void main() {
  group('Home v2 DTO and mapper', () {
    test(
      'preserves contract timestamps, currencies, and decimal strings',
      () async {
        final dto = await loadHomeFixtureDto('populated.json');
        final snapshot = HomeMapper.toDomain(dto);

        expect(dto.generatedAt, '2026-07-11T01:20:00Z');
        expect(dto.dataAsOf, '2026-07-11T01:19:58Z');
        expect(snapshot.generatedAt, DateTime.utc(2026, 7, 11, 1, 20));
        expect(snapshot.dataAsOf, DateTime.utc(2026, 7, 11, 1, 19, 58));
        expect(snapshot.baseCurrency, 'EUR');
        expect(
          snapshot.balance.total,
          Money(amount: '3240.50', currency: 'EUR'),
        );
        expect(snapshot.monthSummary.expense.amount, '847.20');
        expect(snapshot.trend.points, hasLength(30));
        expect(snapshot.primaryGoal?.target.amount, '10000.00');
        expect(snapshot.upcomingPayments, hasLength(3));
        expect(snapshot.recentTransactions, hasLength(3));
      },
    );

    test(
      'accepts nullable computed and transaction metadata without inventing time',
      () async {
        final nullable = HomeMapper.toDomain(
          await loadHomeFixtureDto('nullable_goal.json'),
        );
        final empty = HomeMapper.toDomain(
          await loadHomeFixtureDto('empty_lists.json'),
        );

        expect(nullable.primaryGoal, isNull);
        expect(nullable.balance.deltaPercent, isNull);
        expect(nullable.upcomingPayments, hasLength(1));
        expect(nullable.recentTransactions.single.title, isNull);
        expect(nullable.recentTransactions.single.category, isNull);
        expect(
          nullable.recentTransactions.single.occurredOn,
          DateTime.utc(2026, 7, 10),
        );
        expect(nullable.recentTransactions.single.occurredAt, isNull);
        expect(empty.primaryGoal, isNull);
        expect(empty.trend.points, isEmpty);
        expect(empty.upcomingPayments, isEmpty);
        expect(empty.recentTransactions, isEmpty);
      },
    );

    test(
      'requires nullable contract keys and authoritative occurredOn',
      () async {
        final source = await loadHomeFixtureJson('nullable_goal.json');

        for (final key in const ['deltaPercent']) {
          final json = deepCopyHomeFixture(source);
          final balance = json['balance']! as Map<String, Object?>;
          balance.remove(key);
          expect(
            () => HomeDto.fromJson(json),
            throwsFormatException,
            reason:
                r'$.balance.'
                '$key',
          );
        }

        for (final key in const [
          'title',
          'category',
          'occurredOn',
          'occurredAt',
        ]) {
          final json = deepCopyHomeFixture(source);
          final transactions = json['recentTransactions']! as List<Object?>;
          final transaction = transactions.single! as Map<String, Object?>;
          transaction.remove(key);
          expect(
            () => HomeDto.fromJson(json),
            throwsFormatException,
            reason:
                r'$.recentTransactions[0].'
                '$key',
          );
        }
      },
    );

    test('ignores additive fields and falls back for open enums', () async {
      final snapshot = HomeMapper.toDomain(
        await loadHomeFixtureDto('additive_unknown_fields.json'),
      );

      expect(snapshot.trend.metric, TrendMetric.unknown);
      expect(snapshot.trend.period, TrendPeriod.unknown);
      expect(snapshot.upcomingPayments.single.status, PaymentStatus.unknown);
      expect(
        snapshot.recentTransactions.single.direction,
        TransactionDirection.unknown,
      );
      expect(
        snapshot.recentTransactions.single.status,
        TransactionStatus.confirmed,
      );
      expect(snapshot.availableActions, contains(HomeAction.unknown));
      expect(snapshot.warnings.single.code, 'future_warning');
    });

    test(
      'rejects JSON numbers and malformed decimal strings for money',
      () async {
        final json = await loadHomeFixtureJson('populated.json');
        final balance = Map<String, Object?>.from(
          json['balance']! as Map<String, Object?>,
        );
        json['balance'] = balance;

        balance['amount'] = 3240.50;
        expect(() => HomeDto.fromJson(json), throwsFormatException);

        balance['amount'] = '03.20';
        expect(() => HomeDto.fromJson(json), throwsFormatException);
      },
    );

    test('rejects reversed month boundaries', () async {
      final json = await loadHomeFixtureJson('populated.json');
      final month = Map<String, Object?>.from(
        json['monthSummary']! as Map<String, Object?>,
      );
      json['monthSummary'] = month;
      month['from'] = '2026-07-31';
      month['to'] = '2026-07-01';

      expect(
        () => HomeMapper.toDomain(HomeDto.fromJson(json)),
        throwsFormatException,
      );
    });

    test(
      'defensively caps points and list items while preserving order',
      () async {
        final json = await loadHomeFixtureJson('populated.json');
        final trend = Map<String, Object?>.from(
          json['trend']! as Map<String, Object?>,
        );
        json['trend'] = trend;
        final points = List<Object?>.from(trend['points']! as List<Object?>);
        trend['points'] = [...points, ...points];

        final payments = List<Object?>.from(
          json['upcomingPayments']! as List<Object?>,
        );
        json['upcomingPayments'] = [...payments, payments.first];

        final transactions = List<Object?>.from(
          json['recentTransactions']! as List<Object?>,
        );
        json['recentTransactions'] = [
          ...transactions,
          transactions.first,
          {
            ...transactions.first! as Map<String, Object?>,
            'id': 'pending_fixture',
            'status': 'pending',
          },
        ];

        final snapshot = HomeMapper.toDomain(HomeDto.fromJson(json));

        expect(snapshot.trend.points, hasLength(30));
        expect(snapshot.upcomingPayments, hasLength(3));
        expect(snapshot.upcomingPayments.first.id, 'payment_fixture_1');
        expect(snapshot.recentTransactions, hasLength(3));
        expect(snapshot.recentTransactions.first.id, 'transaction_fixture_1');
        expect(
          snapshot.recentTransactions.every(
            (item) => item.status == TransactionStatus.confirmed,
          ),
          isTrue,
        );
      },
    );

    test(
      'mock repository loads the versioned fixture through DTO mapping',
      () async {
        final repository = MockHomeRepository(delay: Duration.zero);

        final result = await repository.fetchHome() as HomeDataResult;
        final snapshot = result.snapshot;

        expect(snapshot.trend.points, hasLength(30));
        expect(snapshot.upcomingPayments, hasLength(3));
        expect(snapshot.recentTransactions, hasLength(3));
      },
    );

    test(
      'treats the local due date as authoritative and the instant as optional',
      () async {
        final snapshot = await loadHomeFixtureSnapshot('populated.json');
        final payments = snapshot.upcomingPayments;

        // A planned cost carries a calendar date and no time of day, so the
        // contract sends no instant rather than inventing local midnight.
        expect(payments.first.dueOn, DateTime.utc(2026, 7, 16));
        expect(payments.first.dueAt, isNull);

        // An instant is still carried through when one is genuinely known.
        expect(payments[1].dueOn, DateTime.utc(2026, 7, 20));
        expect(payments[1].dueAt, DateTime.utc(2026, 7, 20, 7));
      },
    );

    test('rejects a payment without an authoritative due date', () async {
      final json = await loadHomeFixtureJson('populated.json');
      final payments = List<Object?>.from(
        json['upcomingPayments']! as List<Object?>,
      );
      final first = Map<String, Object?>.from(
        payments.first! as Map<String, Object?>,
      )..remove('dueOn');
      json['upcomingPayments'] = <Object?>[first, ...payments.skip(1)];

      expect(() => HomeDto.fromJson(json), throwsFormatException);
    });
  });
}
