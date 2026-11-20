import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import 'appearance.dart';
import 'cpk_colors.dart';
import 'ligand.dart';
import 'measurement.dart';
import 'van_der_waals.dart';

enum _ImageAction { share, save }

enum _ImageFormat { png, jpeg }

enum _Interaction {
  inspect('Inspect atoms', 0),
  distance('Measure distance', 2),
  angle('Measure bond angle', 3);

  const _Interaction(this.label, this.pointCount);

  final String label;
  final int pointCount;
}

enum _Model {
  ballAndStick('Ball-and-Stick'),
  spaceFilling('Space-Filling'),
  stick('Stick'),
  wireframe('Wireframe');

  const _Model(this.label);

  final String label;
}

class LigandView extends StatefulWidget {
  const LigandView({super.key, required this.ligand, required this.onBack});

  final Ligand ligand;
  final VoidCallback onBack;

  @override
  State<LigandView> createState() => _LigandViewState();
}

class _LigandViewState extends State<LigandView> {
  static const _viewType = 'swifty_protein/molecule';
  static const _imageChannel = MethodChannel('swifty_protein/share');

  MethodChannel? _renderer;
  _Model _model = _Model.ballAndStick;
  _Interaction _interaction = _Interaction.inspect;
  int? _selectedIndex;
  final _measured = <int>[];
  String? _measurementHint;
  late final Int32List _elementGroups;
  int _selectionRequest = 0;
  bool _savingImage = false;
  double _yaw = .3, _pitch = .25, _zoom = 1, _panX = 0, _panY = 0;
  double _lastScale = 1;
  int _lastPointerCount = 0;
  late final Map<String, Object> _geometry;

  @override
  void initState() {
    super.initState();
    final ligand = widget.ligand;
    final groups = <String, int>{};
    _elementGroups = Int32List.fromList([
      for (final atom in ligand.atoms)
        groups.putIfAbsent(switch (atom.element.toUpperCase()) {
          'D' || 'T' => 'H',
          final symbol => symbol,
        }, () => groups.length),
    ]);
    _geometry = {
      'coordinates': Float64List.fromList([
        for (final atom in ligand.atoms) ...[atom.x, atom.y, atom.z],
      ]),
      'colors': Int32List.fromList([
        for (final atom in ligand.atoms) cpkColor(atom.element),
      ]),
      'radii': Float64List.fromList([
        for (final atom in ligand.atoms) vanDerWaalsRadius(atom.element),
      ]),
      'elementGroups': _elementGroups,
      'bonds': Int32List.fromList([
        for (final bond in ligand.bonds) ...[bond.a, bond.b],
      ]),
    };
  }

  void _switchModel(_Model model) {
    final renderer = _renderer;
    if (renderer == null || _model == model) return;
    _dismissInspection();
    setState(() => _model = model);
    unawaited(renderer.invokeMethod<void>('model', model.name));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sendPalette();
  }

  Map<String, int> get _palette {
    final scheme = Theme.of(context).colorScheme;
    return {
      'background': scheme.surfaceContainerLowest.toARGB32().toSigned(32),
      'bond': scheme.outline.toARGB32().toSigned(32),
    };
  }

  void _sendPalette() {
    final renderer = _renderer;
    if (renderer != null) {
      unawaited(renderer.invokeMethod<void>('palette', _palette));
    }
  }

  void _startGesture(ScaleStartDetails details) {
    _dismissInspection();
    _lastScale = 1;
    _lastPointerCount = details.pointerCount;
  }

  void _updateGesture(ScaleUpdateDetails details, Size size) {
    final renderer = _renderer;
    if (renderer == null || size.isEmpty) return;
    if (details.pointerCount != _lastPointerCount) {
      _lastPointerCount = details.pointerCount;
      _lastScale = details.scale;
      return;
    }
    final delta = details.focalPointDelta;
    if (details.pointerCount >= 2) {
      if (_lastScale > 0) {
        _zoom = (_zoom * details.scale / _lastScale).clamp(.25, 8.0);
      }
      _panX += 2 * delta.dx / size.width;
      _panY -= 2 * delta.dy / size.height;
    } else {
      _yaw += delta.dx * .48;
      _pitch += delta.dy * .48;
    }
    _lastScale = details.scale;
    unawaited(
      renderer.invokeMethod<void>('pose', [_yaw, _pitch, _zoom, _panX, _panY]),
    );
  }

  void _dismissInspection() {
    if (_interaction != _Interaction.inspect) return;
    _selectionRequest++;
    if (_selectedIndex == null) return;
    setState(() => _selectedIndex = null);
    _sendHighlight();
  }

  void _setInteraction(_Interaction interaction) {
    _selectionRequest++;
    setState(() {
      _interaction = interaction;
      _selectedIndex = null;
      _measured.clear();
      _measurementHint = null;
    });
    _sendHighlight();
  }

  void _sendHighlight() {
    final renderer = _renderer;
    if (renderer == null) return;
    final inspected = _selectedIndex;
    unawaited(
      renderer.invokeMethod<void>('highlight', [
        inspected == null ? -1 : _elementGroups[inspected],
        for (var i = 0; i < 3; i++) i < _measured.length ? _measured[i] : -1,
      ]),
    );
  }

  Future<void> _pick(Offset point, Size size) async {
    _dismissInspection();
    final request = _selectionRequest;
    final renderer = _renderer;
    if (renderer == null || size.isEmpty) return;

    final index = await renderer.invokeMethod<int>('pick', [
      point.dx / size.width,
      point.dy / size.height,
    ]);
    if (!mounted || request != _selectionRequest || index == null) return;
    if (_interaction == _Interaction.inspect) {
      setState(() => _selectedIndex = index);
      _sendHighlight();
      return;
    }

    setState(() {
      _measurementHint = null;
      if (_measured.length == _interaction.pointCount) _measured.clear();
      if (_measured.contains(index)) {
        _measurementHint = 'Choose a different atom.';
        return;
      }
      if (_interaction == _Interaction.angle && _measured.isNotEmpty) {
        final previous = _measured.last;
        final bonded = widget.ligand.bonds.any(
          (bond) =>
              (bond.a == previous && bond.b == index) ||
              (bond.b == previous && bond.a == index),
        );
        if (!bonded) {
          _measurementHint = 'Choose an atom bonded to the last one.';
          return;
        }
      }
      _measured.add(index);
    });
    _sendHighlight();
  }

  String get _measurementText {
    final hint = _measurementHint;
    if (hint != null) return hint;
    if (_measured.length == _interaction.pointCount) {
      final atoms = widget.ligand.atoms;
      final a = atoms[_measured[0]], b = atoms[_measured[1]];
      if (_interaction == _Interaction.distance) {
        return 'Distance: ${atomDistance(a, b).toStringAsFixed(3)} Å';
      }
      final angle = bondAngleDegrees(a, b, atoms[_measured[2]]);
      return angle == null
          ? 'Angle undefined for overlapping atoms.'
          : 'Bond angle: ${angle.toStringAsFixed(1)}°';
    }
    return switch (_measured.length) {
      0 => 'Tap the first atom.',
      1 when _interaction == _Interaction.angle => 'Tap the middle atom.',
      1 => 'Tap the second atom.',
      _ => 'Tap the third atom.',
    };
  }

  Future<void> _export((_ImageAction, _ImageFormat) selection) async {
    final (action, format) = selection;
    final renderer = _renderer;
    if (renderer == null || _savingImage) return;
    setState(() => _savingImage = true);
    try {
      final image = await renderer
          .invokeMethod<Uint8List>('capture', format.name)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (image == null) throw StateError('The preview is not ready.');
      final saved = await _imageChannel.invokeMethod<bool>(action.name, {
        'image': image,
        'format': format.name,
        'id': widget.ligand.id,
        if (action == _ImageAction.share) ...{
          'title': widget.ligand.shareTitle,
          'message': widget.ligand.shareMessage,
        },
      });
      if (mounted && action == _ImageAction.save && saved == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Molecule image saved.')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not ${action.name} the molecule image.')),
      );
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  Widget _viewport() => PlatformViewLink(
    viewType: _viewType,
    surfaceFactory: (context, controller) => AndroidViewSurface(
      controller: controller as AndroidViewController,
      gestureRecognizers: const {},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    ),
    onCreatePlatformView: (params) {
      final controller = PlatformViewsService.initExpensiveAndroidView(
        id: params.id,
        viewType: _viewType,
        layoutDirection: Directionality.of(context),
        creationParams: {..._geometry, ..._palette},
        creationParamsCodec: const StandardMessageCodec(),
        onFocus: () => params.onFocusChanged(true),
      );
      controller.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
      controller.addOnPlatformViewCreatedListener((id) {
        if (!mounted) return;
        setState(() => _renderer = MethodChannel('$_viewType/$id'));
        _sendPalette();
      });
      unawaited(controller.create());
      return controller;
    },
  );

  @override
  Widget build(BuildContext context) {
    final selected = _selectedIndex;
    final atom = selected == null ? null : widget.ligand.atoms[selected];
    final scheme = Theme.of(context).colorScheme;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 170);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _dismissInspection(),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: Text(widget.ligand.id),
          actions: [
            PopupMenuButton<_Interaction>(
              icon: const Icon(Icons.straighten_outlined),
              tooltip: _interaction == _Interaction.inspect
                  ? 'Measurement tools'
                  : _interaction.label,
              enabled: _renderer != null,
              initialValue: _interaction,
              onSelected: _setInteraction,
              itemBuilder: (_) => [
                for (final mode in _Interaction.values)
                  CheckedPopupMenuItem(
                    value: mode,
                    checked: mode == _interaction,
                    child: Text(mode.label),
                  ),
              ],
            ),
            PopupMenuButton<_Model>(
              icon: const Icon(Icons.view_in_ar_outlined),
              tooltip: 'Visualization model: ${_model.label}',
              enabled: _renderer != null,
              initialValue: _model,
              onSelected: _switchModel,
              itemBuilder: (_) => [
                for (final model in _Model.values)
                  CheckedPopupMenuItem(
                    value: model,
                    checked: model == _model,
                    child: Text(model.label),
                  ),
              ],
            ),
            PopupMenuButton<(_ImageAction, _ImageFormat)>(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share molecule image',
              enabled: _renderer != null && !_savingImage,
              onSelected: _export,
              itemBuilder: (_) => [
                for (final format in _ImageFormat.values)
                  PopupMenuItem(
                    value: (_ImageAction.share, format),
                    child: Text('Share ${format.name.toUpperCase()}'),
                  ),
                const PopupMenuDivider(),
                for (final format in _ImageFormat.values)
                  PopupMenuItem(
                    value: (_ImageAction.save, format),
                    child: Text('Save ${format.name.toUpperCase()} to photos'),
                  ),
              ],
            ),
            const AppearanceButton(),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: scheme.surfaceContainerLowest,
                        child: _viewport(),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _startGesture,
                        onScaleUpdate: (details) =>
                            _updateGesture(details, constraints.biggest),
                        onTapUp: (details) =>
                            _pick(details.localPosition, constraints.biggest),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 12,
                        child: _interaction == _Interaction.inspect
                            ? IgnorePointer(
                                child: AnimatedSwitcher(
                                  duration: motion,
                                  child: atom == null
                                      ? const SizedBox.shrink()
                                      : Align(
                                          key: ValueKey(atom.id),
                                          child: Card(
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Text(
                                                '${atom.element} · ${atom.id}\n'
                                                '(${atom.x.toStringAsFixed(2)}, '
                                                '${atom.y.toStringAsFixed(2)}, '
                                                '${atom.z.toStringAsFixed(2)})',
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              )
                            : Align(
                                alignment: Alignment.topCenter,
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 14),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _measured.isEmpty
                                                ? _measurementText
                                                : '${_measured.map((i) => widget.ligand.atoms[i].id).join(' → ')}\n'
                                                      '$_measurementText',
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Clear measurement',
                                          onPressed: _measured.isEmpty
                                              ? null
                                              : () => _setInteraction(
                                                  _interaction,
                                                ),
                                          icon: const Icon(Icons.restart_alt),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: motion == Duration.zero ? 1 : 0, end: 1),
                duration: motion,
                builder: (_, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    '${widget.ligand.atoms.length} atoms · '
                    '${widget.ligand.bonds.length} bonds\n'
                    'Drag to rotate · Pinch to zoom · Two fingers to pan',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
