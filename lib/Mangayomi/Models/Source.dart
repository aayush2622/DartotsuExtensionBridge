import 'package:objectbox/objectbox.dart';
import '../Eval/dart/model/m_source.dart' as m;

enum ItemType { unknown, manga, anime, novel }

enum SourceCodeLanguage { unknown, dart, javascript }

@Entity()
class MSource {
  @Id()
  int obxId = 0;

  int id;

  String? name;
  String? baseUrl;
  String? lang;
  bool isActive;
  bool isAdded;
  bool isPinned;
  bool isNsfw;
  String? sourceCode;
  String? sourceCodeUrl;
  String? typeSource;
  String? iconUrl;
  bool isFullData;
  bool hasCloudflare;
  bool lastUsed;
  String? dateFormat;
  String? dateFormatLocale;
  String? apiUrl;
  String? version;
  String? versionLast;
  String? headers;
  bool isManga;
  String? appMinVerReq;
  String? additionalParams;
  bool isLocal;
  bool isObsolete;
  String? repo;

  int dbItemType;
  int dbSourceCodeLanguage;

  @Transient()
  ItemType itemType;

  @Transient()
  SourceCodeLanguage sourceCodeLanguage;

  MSource({
    this.id = 0,
    this.name,
    this.baseUrl,
    this.lang,
    this.typeSource,
    this.iconUrl,
    this.dateFormat,
    this.dateFormatLocale,
    this.apiUrl,
    this.sourceCodeUrl,
    this.version = "0.0.1",
    this.versionLast = "0.0.1",
    this.sourceCode,
    this.headers,
    this.repo,
    this.appMinVerReq,
    this.additionalParams,
    this.isActive = true,
    this.isAdded = false,
    this.isNsfw = false,
    this.isFullData = false,
    this.hasCloudflare = false,
    this.isPinned = false,
    this.lastUsed = false,
    this.isManga = true,
    this.isLocal = false,
    this.isObsolete = false,
    ItemType? itemType,
    SourceCodeLanguage? sourceCodeLanguage,
  }) : itemType = itemType ?? ItemType.manga,
       sourceCodeLanguage = sourceCodeLanguage ?? SourceCodeLanguage.dart,
       dbItemType = (itemType ?? ItemType.manga).index,
       dbSourceCodeLanguage =
           (sourceCodeLanguage ?? SourceCodeLanguage.dart).index;

  void syncEnums() {
    itemType = dbItemType >= 0 && dbItemType < ItemType.values.length
        ? ItemType.values[dbItemType]
        : ItemType.unknown;

    sourceCodeLanguage =
        dbSourceCodeLanguage >= 0 &&
            dbSourceCodeLanguage < SourceCodeLanguage.values.length
        ? SourceCodeLanguage.values[dbSourceCodeLanguage]
        : SourceCodeLanguage.unknown;
  }

  factory MSource.fromJson(Map<String, dynamic> json) {
    final obj = MSource(
      id: json['id'] ?? 0,
      name: json['name'],
      baseUrl: json['baseUrl'],
      lang: json['lang'],
      typeSource: json['typeSource'],
      iconUrl: json['iconUrl'],
      dateFormat: json['dateFormat'],
      dateFormatLocale: json['dateFormatLocale'],
      isActive: json['isActive'] ?? true,
      isAdded: json['isAdded'] ?? false,
      isNsfw: json['isNsfw'] ?? false,
      isFullData: json['isFullData'] ?? false,
      hasCloudflare: json['hasCloudflare'] ?? false,
      isPinned: json['isPinned'] ?? false,
      lastUsed: json['lastUsed'] ?? false,
      apiUrl: json['apiUrl'],
      sourceCodeUrl: json['sourceCodeUrl'],
      version: json['version'] ?? "0.0.1",
      versionLast: json['versionLast'] ?? "0.0.1",
      sourceCode: json['sourceCode'],
      headers: json['headers'],
      isManga: json['isManga'] ?? true,
      additionalParams: json['additionalParams'] ?? "",
      isLocal: json['isLocal'] ?? false,
      isObsolete: json['isObsolete'] ?? false,
      repo: json['repo'],
      appMinVerReq: json['appMinVerReq'],
      itemType: ItemType.values[json['itemType'] ?? 0],
      sourceCodeLanguage:
          SourceCodeLanguage.values[json['sourceCodeLanguage'] ?? 0],
    );
    obj.dbItemType = obj.itemType.index;
    obj.dbSourceCodeLanguage = obj.sourceCodeLanguage.index;
    return obj;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'lang': lang,
    'typeSource': typeSource,
    'iconUrl': iconUrl,
    'dateFormat': dateFormat,
    'dateFormatLocale': dateFormatLocale,
    'isActive': isActive,
    'isAdded': isAdded,
    'isNsfw': isNsfw,
    'isFullData': isFullData,
    'hasCloudflare': hasCloudflare,
    'isPinned': isPinned,
    'lastUsed': lastUsed,
    'apiUrl': apiUrl,
    'sourceCodeUrl': sourceCodeUrl,
    'version': version,
    'versionLast': versionLast,
    'sourceCode': sourceCode,
    'headers': headers,
    'isManga': isManga,
    'itemType': dbItemType,
    'sourceCodeLanguage': dbSourceCodeLanguage,
    'appMinVerReq': appMinVerReq,
    'additionalParams': additionalParams,
    'isLocal': isLocal,
    'isObsolete': isObsolete,
    'repo': repo,
  };

  bool get isTorrent => (typeSource?.toLowerCase() ?? "") == "torrent";

  m.MSource toMSource() {
    return m.MSource(
      id: id,
      name: name,
      lang: lang,
      baseUrl: baseUrl,
      apiUrl: apiUrl,
      dateFormat: dateFormat,
      dateFormatLocale: dateFormatLocale,
      hasCloudflare: hasCloudflare,
      isFullData: isFullData,
      additionalParams: additionalParams,
    );
  }
}
