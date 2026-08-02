import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_finance_assistant/features/home/data/home_dto.dart';
import 'package:mobile_finance_assistant/features/home/data/home_repository.dart';

import '../../../support/home_contract_fixture.dart';

void main() {
  test(
    'shared v2 schema is additive and specifies decimal-string money',
    () async {
      final schema = Map<String, Object?>.from(
        jsonDecode(await _homeContractFile().readAsString()) as Map,
      );
      final definitions = schema[r'$defs']! as Map<String, Object?>;
      final decimal = definitions['decimal']! as Map<String, Object?>;
      final properties = schema['properties']! as Map<String, Object?>;
      final balance = properties['balance']! as Map<String, Object?>;
      final balanceProperties = balance['properties']! as Map<String, Object?>;
      final deltaPercent =
          balanceProperties['deltaPercent']! as Map<String, Object?>;
      final recentTransactions =
          properties['recentTransactions']! as Map<String, Object?>;
      final transaction = recentTransactions['items']! as Map<String, Object?>;
      final transactionRequired = transaction['required']! as List<Object?>;

      expect(schema['additionalProperties'], isTrue);
      expect(decimal['type'], 'string');
      expect(decimal['pattern'], contains(r'\.[0-9]+'));
      expect(
        (deltaPercent['oneOf']! as List<Object?>).whereType<Map>().any(
          (choice) => choice['type'] == 'null',
        ),
        isTrue,
      );
      expect(
        transactionRequired,
        containsAll(<String>['title', 'category', 'occurredOn', 'occurredAt']),
      );
      expect(
        schema['required'],
        containsAll(<String>[
          'generatedAt',
          'dataAsOf',
          'baseCurrency',
          'trend',
          'availableActions',
        ]),
      );
      expect(schema['required'], isNot(contains('warnings')));
    },
  );

  test(
    'every versioned fixture is accepted by the DTO contract boundary',
    () async {
      final fixtureNames = [
        'populated.json',
        'empty_lists.json',
        'nullable_goal.json',
        'additive_unknown_fields.json',
      ];

      for (final name in fixtureNames) {
        final value = jsonDecode(await homeFixtureFile(name).readAsString());
        expect(
          () => HomeDto.fromJson(Map<String, Object?>.from(value as Map)),
          returnsNormally,
          reason: name,
        );
      }
    },
  );

  test(
    'contract fixtures never encode monetary fields as JSON numbers',
    () async {
      const monetaryKeys = {
        'amount',
        'deltaAmount',
        'deltaPercent',
        'income',
        'expense',
        'netFlow',
        'total',
        'current',
        'target',
        'progressPercent',
        'monthlyContribution',
      };

      for (final entity
          in homeFixtureDirectory().listSync().whereType<File>()) {
        final value = jsonDecode(await entity.readAsString());
        _expectMonetaryStrings(value, monetaryKeys, entity.path);
      }
    },
  );

  test('maps the granular balance delta warning independently', () {
    expect(homeBlockFromContract('balanceDelta'), HomeBlock.balanceDelta);
    expect(homeBlockFromContract('balance'), HomeBlock.balance);
    expect(homeBlockFromContract('balanceDeltaPercent'), isNull);
  });
}

void _expectMonetaryStrings(Object? value, Set<String> keys, String source) {
  if (value is List) {
    for (final item in value) {
      _expectMonetaryStrings(item, keys, source);
    }
    return;
  }
  if (value is! Map) return;

  for (final entry in value.entries) {
    if (keys.contains(entry.key)) {
      if (entry.key == 'deltaPercent' && entry.value == null) {
        continue;
      }
      expect(entry.value, isA<String>(), reason: '$source: ${entry.key}');
    }
    _expectMonetaryStrings(entry.value, keys, source);
  }
}

File _homeContractFile() {
  final candidates = <File>[
    File('contracts/home/v2/home.schema.json'),
    File('../../packages/contracts/home/v2/home.schema.json'),
  ];
  return candidates.firstWhere(
    (candidate) => candidate.existsSync(),
    orElse: () => throw StateError('Home v2 contract schema was not found.'),
  );
}
