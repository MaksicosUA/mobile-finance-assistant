import 'dart:convert';
import 'dart:io';

import 'package:mobile_finance_assistant/features/home/data/home_dto.dart';
import 'package:mobile_finance_assistant/features/home/data/home_mapper.dart';
import 'package:mobile_finance_assistant/features/home/domain/home_snapshot.dart';

Future<Map<String, Object?>> loadHomeFixtureJson(String name) async {
  final source = await homeFixtureFile(name).readAsString();
  return Map<String, Object?>.from(jsonDecode(source) as Map);
}

Future<HomeDto> loadHomeFixtureDto(String name) async {
  return HomeDto.fromJson(await loadHomeFixtureJson(name));
}

Future<HomeSnapshot> loadHomeFixtureSnapshot(String name) async {
  return HomeMapper.toDomain(await loadHomeFixtureDto(name));
}

HomeSnapshot loadHomeFixtureSnapshotSync(String name) {
  final source = homeFixtureFile(name).readAsStringSync();
  final json = Map<String, Object?>.from(jsonDecode(source) as Map);
  return HomeMapper.toDomain(HomeDto.fromJson(json));
}

Map<String, Object?> deepCopyHomeFixture(Map<String, Object?> value) {
  return Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
}

Directory homeFixtureDirectory() {
  // Fixtures are versioned with the suite in this repository (ADR 0015).
  // `flutter test` runs from the package root, so the path is relative to it.
  final directory = Directory('test/fixtures/home/v2');
  if (!directory.existsSync()) {
    throw StateError(
      'Home v2 test fixtures were not found from ${Directory.current.path}.',
    );
  }
  return directory;
}

File homeFixtureFile(String name) {
  return File('${homeFixtureDirectory().path}/$name');
}
