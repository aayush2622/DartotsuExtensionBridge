class Source {
  String? id;
  String? name;
  String? baseUrl;
  String? lang;
  bool? isNsfw;
  String? iconUrl;
  String? version;
  String? versionLast;
  bool? isObsolete;
  String? repo;
  bool? hasUpdate;
  String? apkUrl;
  String? apkName;
  bool? isShared;

  Source({
    this.id = '',
    this.name = '',
    this.baseUrl = '',
    this.lang = '',
    this.iconUrl = '',
    this.isNsfw = false,
    this.version = "0.0.1",
    this.versionLast = "0.0.1",
    this.isObsolete = false,
    this.repo,
    this.hasUpdate = false,
    this.apkUrl = '',
    this.apkName = '',
    this.isShared = false,
  });

  Source.fromJson(Map<String, dynamic> json) {
    baseUrl = json['baseUrl'];
    iconUrl = json['iconUrl'];
    apkUrl = json['apkUrl'];
    apkName = json['apkName'];
    id = json['id'].toString();
    isNsfw = json['isNsfw'];
    lang = json['lang'];
    name = json['name'];
    version = json['version'];
    versionLast = json['versionLast'];
    isObsolete = json['isObsolete'];
    repo = json['repo'];
    hasUpdate = json['hasUpdate'] ?? false;
    isShared = json['isShared'] ?? false;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apkUrl': apkUrl,
        'apkName': apkName,
        'lang': lang,
        'iconUrl': iconUrl,
        'isNsfw': isNsfw,
        'version': version,
        'versionLast': versionLast,
        'isObsolete': isObsolete,
        'repo': repo,
        'hasUpdate': hasUpdate,
        'isShared': isShared,
      };
}
