/// One entry of a source's native filter/search-options list, as returned by
/// [SourceMethods.getFilterList] and round-tripped back through
/// [SourceMethods.search]'s `filters` argument once the UI has edited the
/// state fields it cares about.
///
/// `type` is one of: `header`, `separator`, `text`, `checkbox`, `tri_state`,
/// `select`, `sort`, `group`. Only the fields that type uses are populated;
/// everything else is null. `group` nests a sub-list of [SourceFilter] under
/// a named heading (e.g. Tachiyomi/Mihon-style sources commonly group
/// related checkboxes this way).
class SourceFilter {
  String type;
  String name;

  /// `text`: the current input value.
  String? textValue;

  /// `checkbox`: whether it's checked.
  bool? checkBoxValue;

  /// `tri_state`: 0 = ignored, 1 = included, 2 = excluded.
  int? triState;

  /// `select`: the chosen index into [selectOptions].
  int? selectIndex;
  List<String>? selectOptions;

  /// `sort`: the chosen index into [sortOptions], and its direction.
  int? sortIndex;
  bool? sortAscending;
  List<String>? sortOptions;

  /// `group`: the filters nested under this heading.
  List<SourceFilter>? group;

  SourceFilter({
    required this.type,
    required this.name,
    this.textValue,
    this.checkBoxValue,
    this.triState,
    this.selectIndex,
    this.selectOptions,
    this.sortIndex,
    this.sortAscending,
    this.sortOptions,
    this.group,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'name': name,
    if (textValue != null) 'textValue': textValue,
    if (checkBoxValue != null) 'checkBoxValue': checkBoxValue,
    if (triState != null) 'triState': triState,
    if (selectIndex != null) 'selectIndex': selectIndex,
    if (selectOptions != null) 'selectOptions': selectOptions,
    if (sortIndex != null) 'sortIndex': sortIndex,
    if (sortAscending != null) 'sortAscending': sortAscending,
    if (sortOptions != null) 'sortOptions': sortOptions,
    if (group != null) 'group': group!.map((e) => e.toJson()).toList(),
  };

  factory SourceFilter.fromJson(Map<String, dynamic> json) => SourceFilter(
    type: json['type'] as String,
    name: json['name'] as String,
    textValue: json['textValue'] as String?,
    checkBoxValue: json['checkBoxValue'] as bool?,
    triState: json['triState'] as int?,
    selectIndex: json['selectIndex'] as int?,
    selectOptions: (json['selectOptions'] as List?)?.cast<String>(),
    sortIndex: json['sortIndex'] as int?,
    sortAscending: json['sortAscending'] as bool?,
    sortOptions: (json['sortOptions'] as List?)?.cast<String>(),
    group: (json['group'] as List?)
        ?.map((e) => SourceFilter.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}
