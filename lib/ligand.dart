class Atom {
  const Atom(this.id, this.element, this.x, this.y, this.z);
  final String id, element;
  final double x, y, z;
}

class Bond {
  const Bond(this.a, this.b);
  final int a, b;
}

class Ligand {
  const Ligand(this.id, this.atoms, this.bonds, {this.name, this.formula});

  final String id;
  final List<Atom> atoms;
  final List<Bond> bonds;
  final String? name, formula;

  String get shareTitle => name == null ? id : '$name ($id)';

  String get shareMessage {
    final molecularFormula = formula ?? _hillFormula(atoms);
    final formulaLabel = formula == null ? 'Formula from model' : 'Formula';
    return '$shareTitle\nAtoms: ${atoms.length}\n$formulaLabel: $molecularFormula';
  }
}

Ligand parseLigand(String id, String source) {
  final lines = source.split(RegExp(r'\r?\n'));
  final atoms = <Atom>[];
  final rawBonds = <(String, String)>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() != 'loop_') continue;
    final headers = <String>[];
    while (++i < lines.length && lines[i].trim().startsWith('_')) {
      headers.add(lines[i].trim());
    }
    if (headers.isEmpty) continue;
    final atomLoop = headers.first.startsWith('_chem_comp_atom.');
    final bondLoop = headers.first.startsWith('_chem_comp_bond.');
    if (!atomLoop && !bondLoop) {
      i--;
      continue;
    }
    final values = <String>[];
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.startsWith('#') ||
          line == 'loop_' ||
          line.startsWith('_') ||
          line.startsWith('data_'))
        break;
      if (line.isNotEmpty) values.addAll(_tokens(line));
      i++;
    }
    i--;
    if (values.length % headers.length != 0)
      throw const FormatException('Incomplete CIF loop');
    int col(String suffix) => headers.indexWhere((h) => h.endsWith('.$suffix'));
    if (atomLoop) {
      final name = col('atom_id'), element = col('type_symbol');
      var x = col('model_Cartn_x'),
          y = col('model_Cartn_y'),
          z = col('model_Cartn_z');
      final modelComplete =
          x >= 0 &&
          y >= 0 &&
          z >= 0 &&
          [
            for (var j = 0; j < values.length; j += headers.length)
              for (final column in [x, y, z]) values[j + column],
          ].every((value) {
            final number = double.tryParse(value);
            return number != null && number.isFinite;
          });
      if (!modelComplete) {
        final idealX = col('pdbx_model_Cartn_x_ideal');
        final idealY = col('pdbx_model_Cartn_y_ideal');
        final idealZ = col('pdbx_model_Cartn_z_ideal');
        if (idealX >= 0 && idealY >= 0 && idealZ >= 0) {
          x = idealX;
          y = idealY;
          z = idealZ;
        }
      }
      if ([name, element, x, y, z].contains(-1)) continue;
      for (var j = 0; j < values.length; j += headers.length) {
        final px = double.tryParse(values[j + x]),
            py = double.tryParse(values[j + y]),
            pz = double.tryParse(values[j + z]);
        if (px == null ||
            py == null ||
            pz == null ||
            !px.isFinite ||
            !py.isFinite ||
            !pz.isFinite)
          continue;
        atoms.add(Atom(values[j + name], values[j + element], px, py, pz));
      }
    } else {
      final a = col('atom_id_1'), b = col('atom_id_2');
      if (a < 0 || b < 0) continue;
      for (var j = 0; j < values.length; j += headers.length) {
        rawBonds.add((values[j + a], values[j + b]));
      }
    }
  }
  if (atoms.isEmpty || atoms.length > 5000)
    throw const FormatException('No usable atoms or molecule too large');
  final indices = {for (var i = 0; i < atoms.length; i++) atoms[i].id: i};
  final bonds = <Bond>[];
  for (final (a, b) in rawBonds) {
    if (indices.containsKey(a) && indices.containsKey(b))
      bonds.add(Bond(indices[a]!, indices[b]!));
  }
  if (bonds.isEmpty && atoms.length > 1)
    throw const FormatException('No usable bonds');
  return Ligand(
    id,
    atoms,
    bonds,
    name: _componentText(lines, 'name'),
    formula: _componentText(lines, 'formula'),
  );
}

String? _componentText(List<String> lines, String field) {
  final tag = RegExp(
    '^_chem_comp\\.$field'
    r'(?=\s|$)',
    caseSensitive: false,
  );
  final quoted = RegExp(r'''^(['"])(.*?)\1(?=\s|$)''');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!tag.hasMatch(line)) continue;
    var value = line.substring('_chem_comp.$field'.length).trimLeft();
    if (value.isEmpty) {
      var next = i + 1;
      while (next < lines.length && lines[next].trim().isEmpty) {
        next++;
      }
      if (next == lines.length) return null;
      if (lines[next].startsWith(';')) {
        final text = <String>[lines[next].substring(1)];
        while (++next < lines.length && !lines[next].startsWith(';')) {
          text.add(lines[next]);
        }
        if (next == lines.length) return null;
        value = text.join(' ');
      } else {
        value = lines[next].trim();
        if (value.startsWith('_') || value.startsWith('#')) return null;
        value =
            quoted.firstMatch(value)?.group(2) ??
            value.split(RegExp(r'\s+')).first;
      }
    } else {
      value =
          quoted.firstMatch(value)?.group(2) ??
          value.split(RegExp(r'\s+')).first;
    }
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty || clean == '.' || clean == '?' || clean.length > 512) {
      return null;
    }
    return clean;
  }
  return null;
}

String _hillFormula(List<Atom> atoms) {
  final counts = <String, int>{};
  final elementSymbol = RegExp(r'^[a-zA-Z]{1,3}$');
  for (final atom in atoms) {
    final text = atom.element.trim();
    if (!elementSymbol.hasMatch(text)) continue;
    final symbol = text[0].toUpperCase() + text.substring(1).toLowerCase();
    counts.update(symbol, (count) => count + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return 'Unavailable';
  final elements = counts.keys.toList()..sort();
  if (elements.remove('C')) {
    final hasHydrogen = elements.remove('H');
    elements.insertAll(0, ['C', if (hasHydrogen) 'H']);
  }
  return elements
      .map(
        (symbol) => counts[symbol] == 1 ? symbol : '$symbol${counts[symbol]}',
      )
      .join();
}

List<String> _tokens(String line) => [
  for (final m in RegExp("(?:'[^']*'|\"[^\"]*\"|\\S+)").allMatches(line))
    m.group(0)!.replaceAll(RegExp(r'''^['"]|['"]$'''), ''),
];
