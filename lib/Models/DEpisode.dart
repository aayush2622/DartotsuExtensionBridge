class DEpisode {
  String? url;
  String? name;
  String? dateUpload;
  String? scanlator;
  String? thumbnail;
  String? description;
  double? episodeNumber;

  DEpisode({
    this.url,
    this.name,
    this.dateUpload,
    this.scanlator,
    this.thumbnail,
    this.description,
    this.episodeNumber,
  });

  factory DEpisode.fromJson(Map<String, dynamic> json) {
    return DEpisode(
      url: json['url'],
      name: json['name'],
      dateUpload: json['dateUpload'] ?? json['date_upload'],
      scanlator: json['scanlator'],
      thumbnail: json['thumbnail'],
      description: json['description'],
      episodeNumber: json['episodeNumber'] != null
          ? double.tryParse(json['episodeNumber'].toString())
          : json['episode_number'] != null
          ? double.tryParse(json['episode_number'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'dateUpload': dateUpload,
    'scanlator': scanlator,
    'thumbnail': thumbnail,
    'description': description,
    'episodeNumber': episodeNumber,
  };
}
