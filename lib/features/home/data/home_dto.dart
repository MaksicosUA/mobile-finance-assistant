import 'package:flutter/foundation.dart';

enum HomePayloadState { ready, firstUseEmpty }

@immutable
class HomeDto {
  const HomeDto({
    this.homeState = HomePayloadState.ready,
    required this.generatedAt,
    required this.dataAsOf,
    required this.baseCurrency,
    required this.user,
    required this.balance,
    required this.monthSummary,
    required this.trend,
    required this.primaryGoal,
    required this.upcomingPayments,
    required this.recentTransactions,
    required this.availableActions,
    required this.warnings,
    this.wallets = const <HomeWalletDto>[],
  });

  factory HomeDto.fromJson(Map<String, Object?> json) {
    final dto = HomeDto(
      homeState: json.containsKey('homeState')
          ? _homePayloadState(json['homeState'])
          : HomePayloadState.ready,
      generatedAt: _utcTimestamp(json['generatedAt'], r'$.generatedAt'),
      dataAsOf: _utcTimestamp(json['dataAsOf'], r'$.dataAsOf'),
      baseCurrency: _currency(json['baseCurrency'], r'$.baseCurrency'),
      user: HomeUserDto.fromJson(_map(json['user'], r'$.user')),
      balance: HomeBalanceDto.fromJson(_map(json['balance'], r'$.balance')),
      monthSummary: HomeMonthSummaryDto.fromJson(
        _map(json['monthSummary'], r'$.monthSummary'),
      ),
      trend: HomeTrendDto.fromJson(_map(json['trend'], r'$.trend')),
      primaryGoal: json['primaryGoal'] == null
          ? null
          : HomeGoalDto.fromJson(_map(json['primaryGoal'], r'$.primaryGoal')),
      upcomingPayments: _list(json['upcomingPayments'], r'$.upcomingPayments')
          .indexed
          .map((entry) {
            return HomePaymentDto.fromJson(
              _map(
                entry.$2,
                r'$.upcomingPayments['
                '${entry.$1}]',
              ),
            );
          })
          .toList(growable: false),
      recentTransactions:
          _list(json['recentTransactions'], r'$.recentTransactions').indexed
              .map((entry) {
                return HomeTransactionDto.fromJson(
                  _map(
                    entry.$2,
                    r'$.recentTransactions['
                    '${entry.$1}]',
                  ),
                );
              })
              .toList(growable: false),
      availableActions: _list(json['availableActions'], r'$.availableActions')
          .indexed
          .map((entry) {
            return _nonEmptyString(
              entry.$2,
              r'$.availableActions['
              '${entry.$1}]',
            );
          })
          .toList(growable: false),
      // Additive: a server that does not send them yet is not an error, and a
      // profile with one account has one entry (ADR 0029).
      wallets: json.containsKey('wallets')
          ? _list(json['wallets'], r'$.wallets').indexed
                .map((entry) {
                  return HomeWalletDto.fromJson(
                    _map(
                      entry.$2,
                      r'$.wallets['
                      '${entry.$1}]',
                    ),
                  );
                })
                .toList(growable: false)
          : const <HomeWalletDto>[],
      warnings: json.containsKey('warnings')
          ? _list(json['warnings'], r'$.warnings').indexed
                .map((entry) {
                  return HomeWarningDto.fromJson(
                    _map(
                      entry.$2,
                      r'$.warnings['
                      '${entry.$1}]',
                    ),
                  );
                })
                .toList(growable: false)
          : const <HomeWarningDto>[],
    );
    if (dto.homeState == HomePayloadState.firstUseEmpty &&
        !_isConsistentFirstUseEmpty(dto)) {
      throw const FormatException(
        r'$.homeState first_use_empty cannot contain financial data or warnings.',
      );
    }
    return dto;
  }

  final HomePayloadState homeState;
  final String generatedAt;
  final String dataAsOf;
  final String baseCurrency;
  final HomeUserDto user;
  final HomeBalanceDto balance;
  final HomeMonthSummaryDto monthSummary;
  final HomeTrendDto trend;
  final HomeGoalDto? primaryGoal;
  final List<HomePaymentDto> upcomingPayments;
  final List<HomeTransactionDto> recentTransactions;
  final List<String> availableActions;
  final List<HomeWarningDto> warnings;
  final List<HomeWalletDto> wallets;
}

/// One wallet beside the balance card. Never summed with another (ADR 0029).
@immutable
class HomeWalletDto {
  const HomeWalletDto({
    required this.accountId,
    required this.name,
    required this.currency,
    required this.balance,
    required this.isDefault,
  });

  factory HomeWalletDto.fromJson(Map<String, Object?> json) {
    final isDefault = json['isDefault'];
    if (isDefault is! bool) {
      throw const FormatException(r'$.wallets[].isDefault must be a boolean.');
    }
    return HomeWalletDto(
      accountId: _nonEmptyString(json['accountId'], r'$.wallets[].accountId'),
      name: _nonEmptyString(json['name'], r'$.wallets[].name'),
      currency: _currency(json['currency'], r'$.wallets[].currency'),
      balance: _decimal(json['balance'], r'$.wallets[].balance'),
      isDefault: isDefault,
    );
  }

  final String accountId;
  final String name;
  final String currency;
  final String balance;
  final bool isDefault;
}

bool _isConsistentFirstUseEmpty(HomeDto dto) {
  final monetaryValues = <String>[
    dto.balance.amount,
    dto.balance.deltaAmount,
    dto.monthSummary.income,
    dto.monthSummary.expense,
    dto.monthSummary.netFlow,
    dto.trend.total,
  ];
  return monetaryValues.every(_isZeroDecimal) &&
      (dto.balance.deltaPercent == null ||
          _isZeroDecimal(dto.balance.deltaPercent!)) &&
      dto.trend.points.isEmpty &&
      dto.primaryGoal == null &&
      dto.upcomingPayments.isEmpty &&
      dto.recentTransactions.isEmpty &&
      dto.warnings.isEmpty;
}

bool _isZeroDecimal(String value) {
  final start = value.startsWith('-') ? 1 : 0;
  for (var index = start; index < value.length; index += 1) {
    final character = value[index];
    if (character != '0' && character != '.') return false;
  }
  return true;
}

@immutable
class HomeUserDto {
  const HomeUserDto({required this.displayName});

  factory HomeUserDto.fromJson(Map<String, Object?> json) {
    return HomeUserDto(
      displayName: _nonEmptyString(json['displayName'], r'$.user.displayName'),
    );
  }

  final String displayName;
}

@immutable
class HomeBalanceDto {
  const HomeBalanceDto({
    required this.amount,
    required this.deltaAmount,
    required this.deltaPercent,
  });

  factory HomeBalanceDto.fromJson(Map<String, Object?> json) {
    return HomeBalanceDto(
      amount: _decimal(json['amount'], r'$.balance.amount'),
      deltaAmount: _decimal(json['deltaAmount'], r'$.balance.deltaAmount'),
      deltaPercent: _requiredNullableDecimal(
        json,
        'deltaPercent',
        r'$.balance.deltaPercent',
      ),
    );
  }

  final String amount;
  final String deltaAmount;
  final String? deltaPercent;
}

@immutable
class HomeMonthSummaryDto {
  const HomeMonthSummaryDto({
    required this.from,
    required this.to,
    required this.income,
    required this.expense,
    required this.netFlow,
  });

  factory HomeMonthSummaryDto.fromJson(Map<String, Object?> json) {
    return HomeMonthSummaryDto(
      from: _date(json['from'], r'$.monthSummary.from'),
      to: _date(json['to'], r'$.monthSummary.to'),
      income: _decimal(json['income'], r'$.monthSummary.income'),
      expense: _decimal(json['expense'], r'$.monthSummary.expense'),
      netFlow: _decimal(json['netFlow'], r'$.monthSummary.netFlow'),
    );
  }

  final String from;
  final String to;
  final String income;
  final String expense;
  final String netFlow;
}

@immutable
class HomeTrendDto {
  const HomeTrendDto({
    required this.metric,
    required this.period,
    required this.total,
    required this.points,
  });

  factory HomeTrendDto.fromJson(Map<String, Object?> json) {
    return HomeTrendDto(
      metric: _nonEmptyString(json['metric'], r'$.trend.metric'),
      period: _nonEmptyString(json['period'], r'$.trend.period'),
      total: _decimal(json['total'], r'$.trend.total'),
      points: _list(json['points'], r'$.trend.points').indexed
          .map((entry) {
            return HomeTrendPointDto.fromJson(
              _map(
                entry.$2,
                r'$.trend.points['
                '${entry.$1}]',
              ),
              entry.$1,
            );
          })
          .toList(growable: false),
    );
  }

  final String metric;
  final String period;
  final String total;
  final List<HomeTrendPointDto> points;
}

@immutable
class HomeTrendPointDto {
  const HomeTrendPointDto({required this.date, required this.amount});

  factory HomeTrendPointDto.fromJson(Map<String, Object?> json, int index) {
    return HomeTrendPointDto(
      date: _date(
        json['date'],
        r'$.trend.points['
        '$index].date',
      ),
      amount: _decimal(
        json['amount'],
        r'$.trend.points['
        '$index].amount',
      ),
    );
  }

  final String date;
  final String amount;
}

@immutable
class HomeGoalDto {
  const HomeGoalDto({
    required this.id,
    required this.title,
    required this.current,
    required this.target,
    required this.currency,
    required this.dueDate,
    required this.progressPercent,
    required this.monthlyContribution,
  });

  factory HomeGoalDto.fromJson(Map<String, Object?> json) {
    return HomeGoalDto(
      id: _nonEmptyString(json['id'], r'$.primaryGoal.id'),
      title: _nonEmptyString(json['title'], r'$.primaryGoal.title'),
      current: _decimal(json['current'], r'$.primaryGoal.current'),
      target: _decimal(json['target'], r'$.primaryGoal.target'),
      currency: _currency(json['currency'], r'$.primaryGoal.currency'),
      dueDate: _date(json['dueDate'], r'$.primaryGoal.dueDate'),
      progressPercent: _decimal(
        json['progressPercent'],
        r'$.primaryGoal.progressPercent',
      ),
      monthlyContribution: _decimal(
        json['monthlyContribution'],
        r'$.primaryGoal.monthlyContribution',
      ),
    );
  }

  final String id;
  final String title;
  final String current;
  final String target;
  final String currency;
  final String dueDate;
  final String progressPercent;
  final String monthlyContribution;
}

@immutable
class HomePaymentDto {
  const HomePaymentDto({
    required this.id,
    required this.title,
    required this.dueOn,
    required this.dueAt,
    required this.amount,
    required this.currency,
    required this.status,
  });

  factory HomePaymentDto.fromJson(Map<String, Object?> json) {
    return HomePaymentDto(
      id: _nonEmptyString(json['id'], r'$.upcomingPayments[].id'),
      title: _nonEmptyString(json['title'], r'$.upcomingPayments[].title'),
      dueOn: _date(json['dueOn'], r'$.upcomingPayments[].dueOn'),
      // Nullable by contract: a planned cost has a local date and no time of
      // day, so the server sends no instant rather than inventing one.
      dueAt: _requiredNullableUtcTimestamp(
        json,
        'dueAt',
        r'$.upcomingPayments[].dueAt',
      ),
      amount: _decimal(json['amount'], r'$.upcomingPayments[].amount'),
      currency: _currency(json['currency'], r'$.upcomingPayments[].currency'),
      status: _nonEmptyString(json['status'], r'$.upcomingPayments[].status'),
    );
  }

  final String id;
  final String title;
  final String dueOn;
  final String? dueAt;
  final String amount;
  final String currency;
  final String status;
}

@immutable
class HomeTransactionDto {
  const HomeTransactionDto({
    required this.id,
    required this.title,
    required this.category,
    required this.occurredOn,
    required this.occurredAt,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.status,
  });

  factory HomeTransactionDto.fromJson(Map<String, Object?> json) {
    return HomeTransactionDto(
      id: _nonEmptyString(json['id'], r'$.recentTransactions[].id'),
      title: _requiredNullableNonEmptyString(
        json,
        'title',
        r'$.recentTransactions[].title',
      ),
      category: _requiredNullableNonEmptyString(
        json,
        'category',
        r'$.recentTransactions[].category',
      ),
      occurredOn: _date(
        json['occurredOn'],
        r'$.recentTransactions[].occurredOn',
      ),
      occurredAt: _requiredNullableUtcTimestamp(
        json,
        'occurredAt',
        r'$.recentTransactions[].occurredAt',
      ),
      amount: _decimal(json['amount'], r'$.recentTransactions[].amount'),
      currency: _currency(json['currency'], r'$.recentTransactions[].currency'),
      direction: _nonEmptyString(
        json['direction'],
        r'$.recentTransactions[].direction',
      ),
      status: _nonEmptyString(json['status'], r'$.recentTransactions[].status'),
    );
  }

  final String id;
  final String? title;
  final String? category;
  final String occurredOn;
  final String? occurredAt;
  final String amount;
  final String currency;
  final String direction;
  final String status;
}

@immutable
class HomeWarningDto {
  const HomeWarningDto({required this.code, required this.block});

  factory HomeWarningDto.fromJson(Map<String, Object?> json) {
    return HomeWarningDto(
      code: _nonEmptyString(json['code'], r'$.warnings[].code'),
      block: _nonEmptyString(json['block'], r'$.warnings[].block'),
    );
  }

  final String code;
  final String block;
}

Map<String, Object?> _map(Object? value, String path) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$path must be an object.');
}

List<Object?> _list(Object? value, String path) {
  if (value is List<Object?>) return value;
  throw FormatException('$path must be an array.');
}

String _nonEmptyString(Object? value, String path) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$path must be a non-empty string.');
}

HomePayloadState _homePayloadState(Object? value) {
  final state = _nonEmptyString(value, r'$.homeState');
  return switch (state) {
    'first_use_empty' => HomePayloadState.firstUseEmpty,
    // Home state is an open enum. Unknown future values retain the v2 ready
    // behavior instead of making an otherwise valid aggregate unusable.
    _ => HomePayloadState.ready,
  };
}

String _decimal(Object? value, String path) {
  final result = _nonEmptyString(value, path);
  if (!RegExp(r'^-?(0|[1-9]\d*)(\.\d+)?$').hasMatch(result)) {
    throw FormatException('$path must be a decimal string.');
  }
  return result;
}

String? _requiredNullableDecimal(
  Map<String, Object?> json,
  String key,
  String path,
) {
  _requireKey(json, key, path);
  final value = json[key];
  return value == null ? null : _decimal(value, path);
}

String? _requiredNullableNonEmptyString(
  Map<String, Object?> json,
  String key,
  String path,
) {
  _requireKey(json, key, path);
  final value = json[key];
  return value == null ? null : _nonEmptyString(value, path);
}

String? _requiredNullableUtcTimestamp(
  Map<String, Object?> json,
  String key,
  String path,
) {
  _requireKey(json, key, path);
  final value = json[key];
  return value == null ? null : _utcTimestamp(value, path);
}

void _requireKey(Map<String, Object?> json, String key, String path) {
  if (!json.containsKey(key)) {
    throw FormatException('$path is required.');
  }
}

String _currency(Object? value, String path) {
  final result = _nonEmptyString(value, path);
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(result)) {
    throw FormatException('$path must be an ISO 4217 currency.');
  }
  return result;
}

String _date(Object? value, String path) {
  final result = _nonEmptyString(value, path);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(result)) {
    throw FormatException('$path must be an ISO-8601 date.');
  }
  final parsed = DateTime.tryParse('${result}T00:00:00Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != result) {
    throw FormatException('$path must be a valid calendar date.');
  }
  return result;
}

String _utcTimestamp(Object? value, String path) {
  final result = _nonEmptyString(value, path);
  final parsed = DateTime.tryParse(result);
  final utcPattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?Z$',
  );
  if (!utcPattern.hasMatch(result) || parsed == null || !parsed.isUtc) {
    throw FormatException('$path must be an ISO-8601 UTC timestamp.');
  }
  _date(result.substring(0, 10), path);
  return result;
}
