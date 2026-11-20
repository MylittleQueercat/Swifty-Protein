import 'package:flutter_test/flutter_test.dart';
import 'package:swifty_protein/ligand.dart';

void main() {
  test('uses ideal coordinates when model coordinates are missing', () {
    const source = '''
data_TEST
loop_
_chem_comp_atom.comp_id
_chem_comp_atom.atom_id
_chem_comp_atom.type_symbol
_chem_comp_atom.model_Cartn_x
_chem_comp_atom.model_Cartn_y
_chem_comp_atom.model_Cartn_z
_chem_comp_atom.pdbx_model_Cartn_x_ideal
_chem_comp_atom.pdbx_model_Cartn_y_ideal
_chem_comp_atom.pdbx_model_Cartn_z_ideal
TEST C1 C ? ? ? 1.0 2.0 3.0
TEST O1 O ? ? ? 2.0 2.0 3.0
#   #
loop_
_chem_comp_bond.comp_id
_chem_comp_bond.atom_id_1
_chem_comp_bond.atom_id_2
TEST C1 O1
#   #
''';

    final ligand = parseLigand('TEST', source);

    expect(ligand.atoms, hasLength(2));
    expect(ligand.atoms.first.x, 1.0);
    expect(ligand.bonds, hasLength(1));
  });
}
