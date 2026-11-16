
enum ModScope {
  all,
  gameplay,
  cosmetic,
}

class ModsFilter {
  const ModsFilter({
    this.scope = ModScope.all,
    this.query,
  });

  final String? query;
  final ModScope scope;

  ModsFilter copyWith({
    String? query,
    ModScope? scope,
  }) {
    return ModsFilter(
      query: query ?? this.query,
      scope: scope ?? this.scope,
    );
  }
}
