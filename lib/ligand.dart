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
  const Ligand(this.id, this.atoms, this.bonds);
  final String id;
  final List<Atom> atoms;
  final List<Bond> bonds;
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
      if (line == '#' ||
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
      if (x < 0 || y < 0 || z < 0) {
        x = col('pdbx_model_Cartn_x_ideal');
        y = col('pdbx_model_Cartn_y_ideal');
        z = col('pdbx_model_Cartn_z_ideal');
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
  return Ligand(id, atoms, bonds);
}

List<String> _tokens(String line) => [
  for (final m in RegExp("(?:'[^']*'|\"[^\"]*\"|\\S+)").allMatches(line))
    m.group(0)!.replaceAll(RegExp(r'''^['"]|['"]$'''), ''),
];
