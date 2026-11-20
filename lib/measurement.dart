import 'dart:math' as math;

import 'ligand.dart';

double atomDistance(Atom a, Atom b) {
  final x = a.x - b.x;
  final y = a.y - b.y;
  final z = a.z - b.z;
  return math.sqrt(x * x + y * y + z * z);
}

double? bondAngleDegrees(Atom a, Atom vertex, Atom c) {
  final ux = a.x - vertex.x, uy = a.y - vertex.y, uz = a.z - vertex.z;
  final vx = c.x - vertex.x, vy = c.y - vertex.y, vz = c.z - vertex.z;
  if ((ux == 0 && uy == 0 && uz == 0) || (vx == 0 && vy == 0 && vz == 0)) {
    return null;
  }
  final x = uy * vz - uz * vy;
  final y = uz * vx - ux * vz;
  final z = ux * vy - uy * vx;
  final dot = ux * vx + uy * vy + uz * vz;
  return math.atan2(math.sqrt(x * x + y * y + z * z), dot) * 180 / math.pi;
}
