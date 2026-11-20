import 'dart:io';
import 'dart:typed_data';

import 'ligand.dart';

class LigandCache {
  LigandCache(this._directory);

  static const maxFileBytes = 5000000;
  static const _maxBytes = 32 * 1024 * 1024;
  static const _maxEntries = 128;
  static final _safeId = RegExp(r'^[A-Z0-9]{1,5}$');

  final Future<Directory?> Function() _directory;
  Future<void> _writes = Future.value();

  Future<Ligand> load(
    String id, {
    required Future<Uint8List> Function() download,
    required Future<Ligand> Function(String, Uint8List) parse,
  }) async {
    final file = await _lookup(id);
    if (file != null) {
      final cached = await _read(file);
      if (cached != null) {
        try {
          final ligand = await parse(id, cached);
          await _touch(file);
          return ligand;
        } on FormatException {
          // Replace malformed cached contents after a successful download.
        }
      }
    }

    final bytes = await download();
    final ligand = await parse(id, bytes);
    if (file != null && bytes.length <= maxFileBytes) {
      // A previous load may still be finishing after the app was locked.
      final write = _writes.then((_) => _store(file, bytes));
      _writes = write;
      await write;
    }
    return ligand;
  }

  Future<File?> _lookup(String id) async {
    final key = id.toUpperCase();
    if (!_safeId.hasMatch(key)) return null;
    final dir = await _directory();
    if (dir == null) return null;
    return File('${dir.path}${Platform.pathSeparator}$key.cif');
  }

  Future<Uint8List?> _read(File file) async {
    try {
      final size = await file.length();
      if (size == 0 || size > maxFileBytes) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      // Reading remains successful if the timestamp cannot be updated.
    }
  }

  Future<void> _store(File file, Uint8List bytes) async {
    final dir = file.parent;
    final staging = File('${dir.path}${Platform.pathSeparator}.pending');
    try {
      await dir.create(recursive: true);
      await staging.writeAsBytes(bytes, flush: true);
      await staging.rename(file.path);
      await _prune(dir, keep: file.path);
    } on FileSystemException {
      try {
        await staging.delete();
      } on FileSystemException {
        // A failed cache write must not prevent opening the ligand.
      }
    }
  }

  Future<void> _prune(Directory dir, {required String keep}) async {
    final entries = <(File, FileStat)>[];
    var total = 0;
    await for (final file in dir.list(followLinks: false)) {
      if (file is! File || !file.path.endsWith('.cif')) continue;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      entries.add((file, stat));
      total += stat.size;
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var count = entries.length;
    for (final (file, stat) in entries) {
      if (count <= _maxEntries && total <= _maxBytes) break;
      if (file.path == keep) continue;
      await file.delete();
      count--;
      total -= stat.size;
    }
  }
}
