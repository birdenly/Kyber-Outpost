String normalizeLanNickname(String name) => name.trim().toLowerCase();

String? validateLanNickname(String name) {
  final value = name.trim();
  if (value.isEmpty || value.length > 16) {
    return 'Use a nickname with 1 to 16 characters.';
  }
  if (value.runes.any((c) => c < 32 || c == 34 || c == 92 || (c >= 127 && c <= 159))) {
    return 'Quotes, backslashes and control characters are not allowed.';
  }
  return null;
}

bool isLanNicknameInUse(String name, Iterable<String> connectedNames) {
  final normalized = normalizeLanNickname(name);
  return connectedNames.any(
    (other) => normalizeLanNickname(other) == normalized,
  );
}
