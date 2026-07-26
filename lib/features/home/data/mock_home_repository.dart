import 'dart:convert';

import 'package:flutter/services.dart';

import 'home_dto.dart';
import 'home_mapper.dart';
import 'home_repository.dart';

enum MockHomeOutcome { populated, empty }

class MockHomeRepository implements HomeRepository {
  MockHomeRepository({
    this.outcome = MockHomeOutcome.populated,
    this.delay = const Duration(milliseconds: 350),
    this.fixtureAsset = 'assets/fixtures/home/v1/populated.json',
    AssetBundle? assetBundle,
  }) : _assetBundle = assetBundle ?? rootBundle;

  final MockHomeOutcome outcome;
  final Duration delay;
  final String fixtureAsset;
  final AssetBundle _assetBundle;

  @override
  Future<HomeRepositoryResult> fetchHome({bool forceRefresh = false}) async {
    await Future<void>.delayed(delay);
    final decoded = jsonDecode(await _assetBundle.loadString(fixtureAsset));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Home fixture root must be an object.');
    }
    final dto = HomeDto.fromJson(decoded);
    if (outcome == MockHomeOutcome.empty) {
      return HomeFirstUseResult(HomeMapper.toFirstUseData(dto));
    }
    return HomeDataResult(HomeMapper.toDomain(dto));
  }
}
