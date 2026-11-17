import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'ligand.dart';
import 'auth.dart';

void main() => runApp(const ProteinApp());

class ProteinApp extends StatelessWidget {
  const ProteinApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Swifty Protein',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff37c9bb),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const AuthGate(child: LigandList()),
  );
}

class LigandList extends StatefulWidget {
  const LigandList({super.key});
  @override
  State<LigandList> createState() => _LigandListState();
}

class _LigandListState extends State<LigandList> {
  List<String> ids = [];
  String query = '';
  String? loading;
  Ligand? current;
  @override
  void initState() {
    super.initState();
    rootBundle.loadString('ligands.txt').then((text) {
      if (mounted)
        setState(
          () => ids = text
              .split(RegExp(r'\r?\n'))
              .map((s) => s.trim())
              .where((s) => RegExp(r'^[A-Za-z0-9]{1,5}$').hasMatch(s))
              .toList(),
        );
    });
  }

  Future<void> open(String id) async {
    setState(() => loading = id);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12);
      try {
        final request = await client
            .getUrl(Uri.parse('https://files.rcsb.org/ligands/view/$id.cif'))
            .timeout(const Duration(seconds: 15));
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        if (response.statusCode == 404)
          throw const HttpException('Ligand not found (404).');
        if (response.statusCode != 200)
          throw HttpException('Server returned ${response.statusCode}.');
        final chunks = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 20),
        )) {
          chunks.addAll(chunk);
          if (chunks.length > 5000000) {
            throw const FormatException('Molecule is too large.');
          }
        }
        final text = const SystemEncoding().decode(chunks);
        final molecule = await compute(_parse, (id, text));
        if (mounted) setState(() => current = molecule);
      } finally {
        client.close(force: true);
      }
    } catch (error) {
      if (mounted) {
        final message = error is TimeoutException
            ? 'Request timeout. Please try again.'
            : error is SocketException
            ? 'No internet connection. Please check your network.'
            : error is FormatException
            ? 'Failed to parse ligand data. ${error.message}'
            : error.toString();
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Could not load ligand'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => loading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (current != null) {
      return LigandView(
        ligand: current!,
        onBack: () => setState(() => current = null),
      );
    }
    final shown = ids
        .where((s) => s.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Swifty Protein')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search ligands',
                border: OutlineInputBorder(),
              ),
              onChanged: (s) => setState(() => query = s),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${shown.length} ligands'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final id = shown[index];
                return ListTile(
                  title: Text(id),
                  leading: const Icon(Icons.bubble_chart),
                  trailing: loading == id
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
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

Ligand _parse((String, String) input) => parseLigand(input.$1, input.$2);

class LigandView extends StatefulWidget {
  const LigandView({super.key, required this.ligand, required this.onBack});
  final Ligand ligand;
  final VoidCallback onBack;
  @override
  State<LigandView> createState() => _LigandViewState();
}

class _LigandViewState extends State<LigandView> {
  static const shareChannel = MethodChannel('swifty_protein/share');
  final imageKey = GlobalKey();
  double yaw = .3, pitch = .25, zoom = 1, startZoom = 1;
  Atom? selected;
  Future<void> shareImage() async {
    try {
      final boundary =
          imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Screenshot failed.');
      await shareChannel.invokeMethod<void>('share', {
        'png': data.buffer.asUint8List(),
        'name': widget.ligand.id,
      });
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share image: $error')),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: widget.onBack,
      ),
      title: Text(widget.ligand.id),
      actions: [
        IconButton(
          icon: const Icon(Icons.share),
          tooltip: 'Share molecule image',
          onPressed: shareImage,
        ),
      ],
    ),
    body: Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              onScaleStart: (_) => startZoom = zoom,
              onScaleUpdate: (details) => setState(() {
                yaw += details.focalPointDelta.dx * .008;
                pitch += details.focalPointDelta.dy * .008;
                zoom = (startZoom * details.scale).clamp(.25, 5);
              }),
              onTapUp: (details) => setState(
                () => selected =
                    MoleculePainter(widget.ligand, yaw, pitch, zoom).atomAt(
                      Size(box.maxWidth, box.maxHeight),
                      details.localPosition,
                    ),
              ),
              child: RepaintBoundary(
                key: imageKey,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: MoleculePainter(widget.ligand, yaw, pitch, zoom),
                ),
              ),
            ),
          ),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${selected!.element} · ${selected!.id}   (${selected!.x.toStringAsFixed(2)}, ${selected!.y.toStringAsFixed(2)}, ${selected!.z.toStringAsFixed(2)})',
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${widget.ligand.atoms.length} atoms · ${widget.ligand.bonds.length} bonds   Drag to rotate · Pinch to zoom',
          ),
        ),
      ],
    ),
  );
}

class MoleculePainter extends CustomPainter {
  MoleculePainter(this.ligand, this.yaw, this.pitch, this.zoom);
  final Ligand ligand;
  final double yaw, pitch, zoom;
  static const colors = {
    'C': Color(0xff999999),
    'H': Colors.white,
    'O': Colors.red,
    'N': Colors.blue,
    'S': Colors.yellow,
    'P': Colors.orange,
    'F': Colors.green,
    'CL': Colors.green,
    'BR': Color(0xffaa3322),
    'I': Color(0xff7b35a8),
  };
  List<(Offset, double, Atom)> project(Size size) {
    final cx =
        ligand.atoms.map((a) => a.x).reduce((a, b) => a + b) /
        ligand.atoms.length;
    final cy =
        ligand.atoms.map((a) => a.y).reduce((a, b) => a + b) /
        ligand.atoms.length;
    final cz =
        ligand.atoms.map((a) => a.z).reduce((a, b) => a + b) /
        ligand.atoms.length;
    final radius = ligand.atoms
        .map(
          (a) => math.sqrt(
            math.pow(a.x - cx, 2) +
                math.pow(a.y - cy, 2) +
                math.pow(a.z - cz, 2),
          ),
        )
        .reduce(math.max)
        .clamp(1.0, double.infinity);
    final scale = math.min(size.width, size.height) * .38 * zoom / radius;
    return [
      for (final a in ligand.atoms)
        () {
          final x = a.x - cx, y = a.y - cy, z = a.z - cz;
          final rx = x * math.cos(yaw) - z * math.sin(yaw),
              rz = x * math.sin(yaw) + z * math.cos(yaw);
          final ry = y * math.cos(pitch) - rz * math.sin(pitch),
              depth = y * math.sin(pitch) + rz * math.cos(pitch);
          return (
            Offset(size.width / 2 + rx * scale, size.height / 2 + ry * scale),
            depth,
            a,
          );
        }(),
    ];
  }

  Atom? atomAt(Size size, Offset point) {
    final hits =
        project(size)
            .where((entry) => (entry.$1 - point).distance < 19)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    return hits.isEmpty ? null : hits.first.$3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff101b29), BlendMode.src);
    final points = project(size);
    final strokes = <(double, void Function())>[];
    for (final bond in ligand.bonds) {
      final a = points[bond.a], b = points[bond.b];
      strokes.add((
        (a.$2 + b.$2) / 2,
        () => canvas.drawLine(
          a.$1,
          b.$1,
          Paint()
            ..color = const Color(0xffaebdca)
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        ),
      ));
    }
    for (final entry in points) {
      strokes.add((
        entry.$2,
        () {
          final color =
              colors[entry.$3.element.toUpperCase()] ?? const Color(0xffbf84d8);
          canvas.drawCircle(entry.$1, 9, Paint()..color = color);
          canvas.drawCircle(
            entry.$1 + const Offset(-2, -2),
            3,
            Paint()..color = Colors.white.withValues(alpha: .3),
          );
        },
      ));
    }
    strokes.sort((a, b) => a.$1.compareTo(b.$1));
    for (final stroke in strokes) {
      stroke.$2();
    }
  }

  @override
  bool shouldRepaint(MoleculePainter old) =>
      old.ligand != ligand ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom;
}
