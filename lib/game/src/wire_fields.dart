/// V1 decoders require exactly their documented fields. An incompatible
/// extension must use its own version so older clients fail predictably.
Map<Object?, Object?> wireObject(
  Object? raw,
  String path,
  Iterable<String> keys,
) {
  if (raw is! Map<Object?, Object?> ||
      raw.length != keys.length ||
      !keys.every(raw.containsKey)) {
    throw FormatException('Invalid fields at $path.');
  }
  return raw;
}

/// Accept mathematically integral JSON numbers equally on Dart VM and web.
int wireInteger(
  Object? raw,
  String path, {
  int min = 0,
  int max = 9007199254740991,
}) {
  if (raw is! num ||
      !raw.isFinite ||
      raw < min ||
      raw > max ||
      raw != raw.truncateToDouble()) {
    throw FormatException('Invalid integer at $path.');
  }
  return raw.toInt();
}
