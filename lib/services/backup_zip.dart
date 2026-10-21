import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/exercise.dart';
import '../models/nutrition.dart';
import '../models/note.dart';
import '../models/progress_shot.dart';
import '../state/fit_state.dart';
import 'alarm_store.dart';
import 'local_store.dart';
import 'media_store.dart';

const String kBackupJsonEntry = 'gymmane.json';
const String _imagesDir = 'media/images';
const String _videosDir = 'media/videos';
const String _notesDir = 'media/notes';
const String _timelineDir = 'timeline';
const String _momentsDir = 'moments';
const String _foodsDir = 'foods';
const String _alarmDir = 'alarm';

bool looksLikeZip(Uint8List b) =>
    b.length > 4 && b[0] == 0x50 && b[1] == 0x4B && (b[2] == 0x03 || b[2] == 0x05 || b[2] == 0x07);

Future<Uint8List> buildBackupZip() async {
  final data = fit.toJson();
  final archive = Archive();
  final used = <String>{};
  final paths = <String, String>{};

  for (final entry in fit.exerciseMedia.entries) {
    final bytes = await MediaStore.readBytes(entry.value);
    if (bytes == null || bytes.isEmpty) continue;
    final ex = fit.exerciseById(entry.key);
    final dir = MediaStore.isVideo(entry.value) ? _videosDir : _imagesDir;
    final name = _uniqueName(
      used,
      slugify(ex == null ? entry.key : exerciseName(ex)),
      MediaStore.extOf(entry.value),
    );
    archive.addFile(ArchiveFile.noCompress('$dir/$name', bytes.length, bytes));
    paths[entry.key] = '$dir/$name';
  }
  data['media'] = paths;

  final noteMedia = <String, String>{};
  for (final note in fit.notes) {
    for (final m in note.media) {
      if (noteMedia.containsKey(m)) continue;
      final bytes = await MediaStore.readBytes(m);
      if (bytes == null || bytes.isEmpty) continue;
      final name = _uniqueName(used, _noteSlug(note), MediaStore.extOf(m));
      archive.addFile(ArchiveFile.noCompress('$_notesDir/$name', bytes.length, bytes));
      noteMedia[m] = '$_notesDir/$name';
    }
  }
  data['noteMedia'] = noteMedia;

  final shotMedia = <String, String>{};
  for (final entry in fit.timelineAsc) {
    for (final pose in kPoses) {
      final name = entry.shot(pose);
      if (name == null || shotMedia.containsKey(name)) continue;
      final bytes = await MediaStore.readBytes(name);
      if (bytes == null || bytes.isEmpty) continue;
      final path = '$_timelineDir/${_day(entry.date)}/$pose.${MediaStore.extOf(name)}';
      used.add(path);
      archive.addFile(ArchiveFile.noCompress(path, bytes.length, bytes));
      shotMedia[name] = path;
    }
  }
  data['shotMedia'] = shotMedia;

  final momentMedia = <String, String>{};
  for (final moment in fit.moments) {
    if (momentMedia.containsKey(moment.file)) continue;
    final bytes = await MediaStore.readBytes(moment.file);
    if (bytes == null || bytes.isEmpty) continue;
    final path =
        '$_momentsDir/${_day(moment.date)}-${momentMedia.length + 1}'
        '.${MediaStore.extOf(moment.file)}';
    used.add(path);
    archive.addFile(ArchiveFile.noCompress(path, bytes.length, bytes));
    momentMedia[moment.file] = path;
  }
  data['momentMedia'] = momentMedia;

  final foodMedia = <String, String>{};
  for (final (photo, label) in [
    for (final f in fit.foods) (f.photo, f.name),
    for (final s in fit.supplements) (s.photo, s.name),
  ]) {
    if (photo.isEmpty || isAssetPhoto(photo) || foodMedia.containsKey(photo)) continue;
    final bytes = await MediaStore.readBytes(photo);
    if (bytes == null || bytes.isEmpty) continue;
    final name = _uniqueName(used, slugify(label), MediaStore.extOf(photo));
    archive.addFile(ArchiveFile.noCompress('$_foodsDir/$name', bytes.length, bytes));
    foodMedia[photo] = '$_foodsDir/$name';
  }
  data['foodMedia'] = foodMedia;

  final alarm = fit.alarmSound;
  final alarmPath = alarm == null ? null : AlarmStore.pathFor(alarm);
  if (alarm != null && alarmPath != null) {
    try {
      final bytes = await File(alarmPath).readAsBytes();
      archive.addFile(ArchiveFile.noCompress('$_alarmDir/$alarm', bytes.length, bytes));
    } catch (_) {}
  }

  archive.addFile(
    ArchiveFile.string(kBackupJsonEntry, const JsonEncoder.withIndent('  ').convert(Store.finite(data))),
  );
  return ZipEncoder().encodeBytes(archive);
}

Future<bool> restoreBackupZip(Uint8List zipBytes) async {
  final staged = <String>[];
  String? stagedAlarm;
  try {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final names = <String>{};
    var expandedSize = 0;
    for (final file in archive.files) {
      expandedSize += file.size;
      if (!names.add(file.name) ||
          file.name.startsWith('/') ||
          file.name.contains('\\') ||
          file.name.split('/').contains('..') ||
          expandedSize > 512 * 1024 * 1024) {
        throw const FormatException('Unsafe or oversized backup');
      }
    }
    final jsonFile = _findJson(archive);
    if (jsonFile == null || jsonFile.size > 32 * 1024 * 1024) return false;
    final data = jsonDecode(utf8.decode(jsonFile.readBytes() ?? const [])) as Map<String, dynamic>;
    FitState.validateBackup(data);

    // Validate every media reference before writing any file. Staged names are
    // unique and originals remain in place until the durable document commits.
    final media = <String, Map<String, String>>{};
    for (final field in ['media', 'noteMedia', 'shotMedia', 'momentMedia', 'foodMedia']) {
      final references = ((data[field] as Map?) ?? {}).cast<String, String>();
      media[field] = references;
      for (final path in references.values) {
        final file = archive.findFile(path);
        if (file == null || !file.isFile || file.readBytes() == null) {
          throw FormatException('Missing backup media: $path');
        }
      }
    }
    final restored = <String, Map<String, String>>{};
    for (final group in media.entries) {
      final remapped = <String, String>{};
      for (final entry in group.value.entries) {
        final bytes = archive.findFile(entry.value)!.readBytes()!;
        final base = await MediaStore.saveBytes('restore', MediaStore.extOf(entry.value), bytes);
        if (base == null) throw StateError('Cannot stage backup media');
        staged.add(base);
        remapped[entry.key] = base;
      }
      restored[group.key] = remapped;
    }
    final alarmName = data['alarmSound'] as String?;
    if (alarmName != null && alarmName.isNotEmpty) {
      final file = archive.findFile('$_alarmDir/$alarmName');
      if (file == null) throw const FormatException('Missing alarm media');
      stagedAlarm = await AlarmStore.saveBytes(alarmName, file.readBytes()!, replace: false);
      if (stagedAlarm == null) throw StateError('Cannot stage alarm');
      data['alarmSound'] = stagedAlarm;
    }
    await fit.restoreBackup(
      data,
      restoredMedia: restored['media'],
      restoredNoteMedia: restored['noteMedia'],
      restoredShots: restored['shotMedia'],
      restoredMoments: restored['momentMedia'],
      restoredFoods: restored['foodMedia'],
    );
    // Retain old files: backups and other account namespaces may still reference
    // them. A separate reference-aware collector can reclaim unreferenced media.
    return true;
  } catch (_) {
    for (final name in staged) {
      await MediaStore.delete(name);
    }
    if (stagedAlarm != null) await AlarmStore.delete(stagedAlarm);
    return false;
  }
}

ArchiveFile? _findJson(Archive a) {
  ArchiveFile? fallback;
  for (final f in a.files) {
    if (!f.isFile || !f.name.toLowerCase().endsWith('.json')) continue;
    if (f.name == kBackupJsonEntry) return f;
    fallback ??= f;
  }
  return fallback;
}

String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _noteSlug(GymNote n) {
  final day = _day(n.date);
  final title = slugify(n.title);
  final short = title.length <= 28 ? title : title.substring(0, 28);
  return short.isEmpty ? day : '$day-$short';
}

String _two(int n) => n.toString().padLeft(2, '0');

String _uniqueName(Set<String> used, String slug, String ext) {
  final base = slug.isEmpty ? 'exercise' : slug;
  var name = '$base.$ext';
  var n = 2;
  while (!used.add(name)) {
    name = '$base-$n.$ext';
    n++;
  }
  return name;
}

const Map<String, String> _fold = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ß': 'ss',
};

String slugify(String name) {
  final buffer = StringBuffer();
  for (final ch in name.toLowerCase().split('')) {
    final folded = _fold[ch] ?? ch;
    if (RegExp(r'^[a-z0-9]+$').hasMatch(folded)) {
      buffer.write(folded);
    } else {
      buffer.write('-');
    }
  }
  return buffer.toString().replaceAll(RegExp('-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
}
