String medicationDisplayName(String rawName) {
  var name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty) return name;

  const groupSuffixes = [
    'Pill',
    'Oral Product',
    'Chewable Product',
    'Oral Liquid Product',
    'Injectable Product',
    'Inhalant Product',
    'Nasal Product',
    'Ophthalmic Product',
    'Topical Product',
  ];
  for (final suffix in groupSuffixes) {
    name = name.replaceFirst(
      RegExp('\\s+${RegExp.escape(suffix)}\$', caseSensitive: false),
      '',
    );
  }

  if (name.isEmpty) return rawName.trim();
  return '${name[0].toUpperCase()}${name.substring(1)}';
}
