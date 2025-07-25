class DEpisode {
  String? url;
  String? name;
  String? dateUpload;
  String? scanlator;
  String? thumbnail;
  String? description;
  bool? filler;
  String episodeNumber;

  DEpisode({
    this.url,
    this.name,
    this.dateUpload,
    this.scanlator,
    this.thumbnail,
    this.description,
    this.filler,
    required this.episodeNumber,
  });

  factory DEpisode.fromJson(Map<String, dynamic> json) {
    return DEpisode(
      url: json['url'],
      name: json['name'],
      dateUpload: json['dateUpload'] ?? json['date_upload'],
      scanlator: json['scanlator'],
      thumbnail: json['thumbnail'],
      description: json['description'],
      filler: json['filler'],
      episodeNumber:
          (double.tryParse(json['episodeNumber'].toString()) ??
                  double.tryParse(json['episode_number'].toString()))!
              .toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'dateUpload': dateUpload,
    'scanlator': scanlator,
    'thumbnail': thumbnail,
    'description': description,
    'filler': filler,
    'episodeNumber': episodeNumber,
  };
}
