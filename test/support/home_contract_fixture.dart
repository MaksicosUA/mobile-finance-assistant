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
  final candidates = <Directory>[
    Directory('../apps/mobile/test/fixtures/home/v2'),
    Directory('apps/mobile/test/fixtures/home/v2'),
  ];
  return candidates.firstWhere(
    (candidate) => candidate.existsSync(),
    orElse: () => throw StateError(
      'External Home v2 test fixtures were not found from '
      '${Directory.current.path}.',
    ),
  );
}

File homeFixtureFile(String name) {
  return File('${homeFixtureDirectory().path}/$name');
}
