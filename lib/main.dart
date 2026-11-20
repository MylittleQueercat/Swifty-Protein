import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';
import 'auth.dart';
import 'launch_screen.dart';
import 'ligand.dart';
import 'ligand_cache.dart';
import 'ligand_view.dart';

void main() => runApp(const ProteinApp());

class ProteinApp extends StatefulWidget {
  const ProteinApp({super.key});

  @override
  State<ProteinApp> createState() => _ProteinAppState();
}

class _ProteinAppState extends State<ProteinApp> {
  static const _settings = MethodChannel('swifty_protein/settings');
  static final _lightTheme = buildAppTheme(Brightness.light);
  static final _darkTheme = buildAppTheme(Brightness.dark);
  ThemeMode _mode = ThemeMode.system;
  bool _modeWasSelected = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreAppearance());
  }

  Future<void> _restoreAppearance() async {
    try {
      final saved = await _settings.invokeMethod<String>('getAppearance');
      if (!mounted || _modeWasSelected) return;
      setState(() {
        _mode = switch (saved) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
      });
    } on MissingPluginException {
      // Follow the platform setting when storage is unavailable.
    } on PlatformException {
      // Follow the platform setting when storage is unavailable.
    }
  }

  Future<void> _setAppearance(ThemeMode mode) async {
    _modeWasSelected = true;
    setState(() => _mode = mode);
    try {
      await _settings.invokeMethod<void>('setAppearance', mode.name);
    } on MissingPluginException {
      // Keep the chosen appearance for this session.
    } on PlatformException {
      // Keep the chosen appearance for this session.
    }
  }

  @override
  Widget build(BuildContext context) => Appearance(
    mode: _mode,
    onChanged: _setAppearance,
    child: MaterialApp(
      title: 'Swifty Protein',
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: _mode,
      home: const LaunchScreen(child: AuthGate(child: LigandList())),
    ),
  );
}

class LigandList extends StatefulWidget {
  const LigandList({super.key});
  @override
  State<LigandList> createState() => _LigandListState();
}

class _LigandListState extends State<LigandList> {
  static final _cache = LigandCache(() async {
    try {
      const settings = MethodChannel('swifty_protein/settings');
      final path = await settings.invokeMethod<String>('ligandCacheDirectory');
      return path == null ? null : Directory(path);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  });

  List<({String id, String searchId})> _ids = [];
  List<({String id, String searchId})> _shown = [];
  final _search = TextEditingController();
  String? loading;
  Ligand? current;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('ligands.txt').then((text) {
      if (!mounted) return;
      _ids = [
        for (final line in const LineSplitter().convert(text))
          if (line.trim().isNotEmpty)
            (id: line.trim(), searchId: line.trim().toLowerCase()),
      ];
      _filter(_search.text);
    });
  }

  void _filter(String query) {
    final term = query.toLowerCase();
    setState(() {
      _shown = term.isEmpty
          ? _ids
          : _ids.where((entry) => entry.searchId.contains(term)).toList();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> open(String id) async {
    if (loading != null) return;
    setState(() => loading = id);

    final Ligand molecule;
    try {
      molecule = await _cache.load(
        id,
        download: () => _downloadCif(id),
        parse: (id, bytes) => compute(_parse, (id, bytes)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => loading = null);
      final message = switch (error) {
        TimeoutException() => 'Request timeout. Please try again.',
        SocketException() =>
          'No internet connection. Please check your network.',
        FormatException() =>
          'Failed to parse ligand data. The file may be corrupted.',
        _LigandLoadFailure(:final message) => message,
        _ => 'Could not download the ligand from RCSB. Please try again.',
      };
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Could not load ligand'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      loading = null;
      current = molecule;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (current != null) {
      return LigandView(
        ligand: current!,
        onBack: () => setState(() => current = null),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swifty Protein'),
        actions: const [AppearanceButton()],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 4,
            child: loading == null
                ? null
                : LinearProgressIndicator(semanticsLabel: 'Loading $loading'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search ligands',
              ),
              onChanged: _filter,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedSwitcher(
                duration: motion,
                child: Text(
                  '${_shown.length} ligands',
                  key: ValueKey(_shown.length),
                  style: TextStyle(color: scheme.tertiary),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: _shown.length,
              itemBuilder: (context, index) {
                final id = _shown[index].id;
                return _LigandCard(
                  id: id,
                  loading: loading == id,
                  onTap: loading == null ? () => open(id) : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LigandCard extends StatelessWidget {
  const _LigandCard({required this.id, required this.loading, this.onTap});

  final String id;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: loading ? scheme.tertiary : scheme.outlineVariant,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: brandPine,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      'assets/brand/molecule.png',
                      width: 26,
                      height: 26,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(id, style: theme.textTheme.titleMedium)),
                if (loading)
                  Text('Loading…', style: TextStyle(color: scheme.tertiary))
                else
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LigandLoadFailure implements Exception {
  const _LigandLoadFailure(this.message);

  final String message;
}

Future<Uint8List> _downloadCif(String id) async {
  final client = HttpClient();
  try {
    final request = await client
        .getUrl(Uri.parse('https://files.rcsb.org/ligands/view/$id.cif'))
        .timeout(const Duration(seconds: 15));
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode == HttpStatus.notFound) {
      throw const _LigandLoadFailure(
        'Ligand not found (404). This ligand may not exist in the database.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw _LigandLoadFailure(
        'RCSB returned HTTP ${response.statusCode}. Please try again.',
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > LigandCache.maxFileBytes) {
        throw const _LigandLoadFailure('The ligand file is too large to load.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}

Ligand _parse((String, Uint8List) input) =>
    parseLigand(input.$1, utf8.decode(input.$2));
