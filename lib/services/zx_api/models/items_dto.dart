class ItemsDto {
  int? _took;
  bool? _timedOut;
  Shards? _shards;
  Hits? _hits;

  int? get took => _took;
  bool? get timedOut => _timedOut;
  Shards? get shards => _shards;
  Hits? get hits => _hits;

  ItemsDto({int? took, bool? timedOut, Shards? shards, Hits? hits}) {
    _took = took;
    _timedOut = timedOut;
    _shards = shards;
    _hits = hits;
  }

  ItemsDto.fromJson(dynamic json) {
    _took = json["took"];
    _timedOut = json["timed_out"];
    _shards = json["_shards"] != null ? Shards.fromJson(json["_shards"]) : null;
    _hits = json["hits"] != null ? Hits.fromJson(json["hits"]) : null;
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["took"] = _took;
    map["timed_out"] = _timedOut;
    if (_shards != null) map["_shards"] = _shards!.toJson();
    if (_hits != null) map["hits"] = _hits!.toJson();
    return map;
  }
}

class Hits {
  Total? _total;
  dynamic _maxScore;
  List<Hits>? _hits;
  dynamic _id;
  Source? _source;

  Total? get total => _total;
  dynamic get maxScore => _maxScore;
  List<Hits>? get hits => _hits;
  dynamic get id => _id;
  Source? get source => _source;

  Hits({dynamic id, Source? source, Total? total, dynamic maxScore, List<Hits>? hits}) {
    _total = total;
    _maxScore = maxScore;
    _hits = hits;
    _id = id;
    _source = source;
  }

  Hits.fromJson(dynamic json) {
    _total = json["total"] != null ? Total.fromJson(json["total"]) : null;
    _source = json["_source"] != null ? Source.fromJson(json["_source"]) : null;
    _maxScore = json["max_score"];
    _id = json["_id"];
    if (json["hits"] != null) {
      _hits = [];
      json["hits"].forEach((v) {
        _hits!.add(Hits.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    if (_total != null) map["total"] = _total!.toJson();
    map["max_score"] = _maxScore;
    if (_hits != null) map["hits"] = _hits!.map((v) => v.toJson()).toList();
    return map;
  }
}

class Source {
  dynamic _originalDayOfRelease;
  String? _availability;
  String? _title;
  List<Releases>? _releases;
  dynamic _originalMonthOfRelease;
  Score? _score;
  String? _genreType;
  List<AdditionalDownloads>? _additionalDownloads;
  List<Screens>? _screens;
  int? _originalYearOfRelease;
  String? _genre;
  List<Publishers>? _publishers;
  String? _genreSubType;
  String? _machineType;
  List<Authors>? _authors;
  OriginalPrice? _originalPrice;
  String? _remarks;
  List<Tosec>? _tosec;

  dynamic get originalDayOfRelease => _originalDayOfRelease;
  String? get availability => _availability;
  String? get title => _title;
  List<Releases>? get releases => _releases;
  dynamic get originalMonthOfRelease => _originalMonthOfRelease;
  Score? get score => _score;
  String? get genreType => _genreType;
  List<AdditionalDownloads>? get additionalDownloads => _additionalDownloads;
  List<Screens>? get screens => _screens;
  int? get originalYearOfRelease => _originalYearOfRelease;
  String? get genre => _genre;
  List<Publishers>? get publishers => _publishers;
  String? get genreSubType => _genreSubType;
  String? get machineType => _machineType;
  List<Authors>? get authors => _authors;
  OriginalPrice? get originalPrice => _originalPrice;
  String? get remarks => _remarks;
  List<Tosec>? get tosec => _tosec;

  Source.fromJson(dynamic json) {
    _originalDayOfRelease = json["originalDayOfRelease"];
    _availability = json["availability"];
    _title = json["title"];
    if (json["releases"] != null) {
      _releases = [];
      json["releases"].forEach((v) {
        _releases!.add(Releases.fromJson(v));
      });
    }
    _originalMonthOfRelease = json["originalMonthOfRelease"];
    _score = json["score"] != null ? Score.fromJson(json["score"]) : null;
    _genreType = json["genreType"];
    if (json["additionalDownloads"] != null) {
      _additionalDownloads = [];
      json["additionalDownloads"].forEach((v) {
        _additionalDownloads!.add(AdditionalDownloads.fromJson(v));
      });
    }
    if (json["screens"] != null) {
      _screens = [];
      json["screens"].forEach((v) {
        _screens!.add(Screens.fromJson(v));
      });
    }
    _originalYearOfRelease = json["originalYearOfRelease"];
    _genre = json["genre"];
    if (json["publishers"] != null) {
      _publishers = [];
      json["publishers"].forEach((v) {
        _publishers!.add(Publishers.fromJson(v));
      });
    }
    _genreSubType = json["genreSubType"];
    _machineType = json["machineType"];
    if (json["authors"] != null) {
      _authors = [];
      json["authors"].forEach((v) {
        _authors!.add(Authors.fromJson(v));
      });
    }
    _originalPrice = json["originalPrice"] != null
        ? OriginalPrice.fromJson(json["originalPrice"])
        : null;
    _remarks = json["remarks"];
    if (json["tosec"] != null) {
      _tosec = [];
      json["tosec"].forEach((v) {
        _tosec!.add(Tosec.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["originalDayOfRelease"] = _originalDayOfRelease;
    map["availability"] = _availability;
    map["title"] = _title;
    if (_releases != null) map["releases"] = _releases!.map((v) => v.toJson()).toList();
    map["originalMonthOfRelease"] = _originalMonthOfRelease;
    if (_score != null) map["score"] = _score!.toJson();
    map["genreType"] = _genreType;
    if (_additionalDownloads != null) {
      map["additionalDownloads"] = _additionalDownloads!.map((v) => v.toJson()).toList();
    }
    if (_screens != null) map["screens"] = _screens!.map((v) => v.toJson()).toList();
    map["originalYearOfRelease"] = _originalYearOfRelease;
    map["genre"] = _genre;
    if (_publishers != null) map["publishers"] = _publishers!.map((v) => v.toJson()).toList();
    map["genreSubType"] = _genreSubType;
    map["machineType"] = _machineType;
    if (_authors != null) map["authors"] = _authors!.map((v) => v.toJson()).toList();
    if (_originalPrice != null) map["originalPrice"] = _originalPrice!.toJson();
    map["remarks"] = _remarks;
    if (_tosec != null) map["tosec"] = _tosec!.map((v) => v.toJson()).toList();
    return map;
  }
}

class Tosec {
  String? _path;
  String? get path => _path;

  Tosec({String? path}) {
    _path = path;
  }

  Tosec.fromJson(dynamic json) {
    _path = json["path"];
  }

  Map<String, dynamic> toJson() {
    return {"path": _path};
  }
}

class OriginalPrice {
  String? _amount;
  String? _currency;

  String? get amount => _amount;
  String? get currency => _currency;

  OriginalPrice({String? amount, String? currency}) {
    _amount = amount;
    _currency = currency;
  }

  OriginalPrice.fromJson(dynamic json) {
    _amount = json["amount"];
    _currency = json["currency"];
  }

  Map<String, dynamic> toJson() {
    return {"amount": _amount, "currency": _currency};
  }
}

class Authors {
  String? _country;
  dynamic _groupName;
  dynamic _groupType;
  List<dynamic>? _notes;
  dynamic _groupCountry;
  int? _authorSeq;
  List<dynamic>? _roles;
  String? _name;
  String? _labelType;
  String? _type;

  String? get country => _country;
  dynamic get groupName => _groupName;
  dynamic get groupType => _groupType;
  List<dynamic>? get notes => _notes;
  dynamic get groupCountry => _groupCountry;
  int? get authorSeq => _authorSeq;
  List<dynamic>? get roles => _roles;
  String? get name => _name;
  String? get labelType => _labelType;
  String? get type => _type;

  Authors.fromJson(dynamic json) {
    _country = json["country"];
    _groupName = json["groupName"];
    _groupType = json["groupType"];
    if (json["notes"] != null) {
      _notes = [];
      json["notes"].forEach((v) { _notes!.add(v); });
    }
    _groupCountry = json["groupCountry"];
    _authorSeq = json["authorSeq"];
    if (json["roles"] != null) {
      _roles = [];
      json["roles"].forEach((v) { _roles!.add(v); });
    }
    _name = json["name"];
    _labelType = json["labelType"];
    _type = json["type"];
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["country"] = _country;
    map["groupName"] = _groupName;
    map["groupType"] = _groupType;
    map["notes"] = _notes;
    map["groupCountry"] = _groupCountry;
    map["authorSeq"] = _authorSeq;
    map["roles"] = _roles;
    map["name"] = _name;
    map["labelType"] = _labelType;
    map["type"] = _type;
    return map;
  }
}

class Publishers {
  String? _country;
  List<dynamic>? _notes;
  String? _name;
  String? _labelType;
  int? _publisherSeq;

  String? get country => _country;
  List<dynamic>? get notes => _notes;
  String? get name => _name;
  String? get labelType => _labelType;
  int? get publisherSeq => _publisherSeq;

  Publishers.fromJson(dynamic json) {
    _country = json["country"];
    if (json["notes"] != null) {
      _notes = [];
      json["notes"].forEach((v) { _notes!.add(v); });
    }
    _name = json["name"];
    _labelType = json["labelType"];
    _publisherSeq = json["publisherSeq"];
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["country"] = _country;
    map["notes"] = _notes;
    map["name"] = _name;
    map["labelType"] = _labelType;
    map["publisherSeq"] = _publisherSeq;
    return map;
  }
}

class Screens {
  String? _filename;
  int? _size;
  String? _format;
  String? _type;
  dynamic _title;
  String? _url;

  String? get filename => _filename;
  int? get size => _size;
  String? get format => _format;
  String? get type => _type;
  dynamic get title => _title;
  String? get url => _url;

  Screens.fromJson(dynamic json) {
    _filename = json["filename"];
    _size = json["size"];
    _format = json["format"];
    _type = json["type"];
    _title = json["title"];
    _url = json["url"];
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["filename"] = _filename;
    map["size"] = _size;
    map["format"] = _format;
    map["type"] = _type;
    map["title"] = _title;
    map["url"] = _url;
    return map;
  }
}

class AdditionalDownloads {
  String? _path;
  int? _size;
  String? _format;
  dynamic _language;
  String? _type;

  String? get path => _path;
  int? get size => _size;
  String? get format => _format;
  dynamic get language => _language;
  String? get type => _type;

  AdditionalDownloads.fromJson(dynamic json) {
    _path = json["path"];
    _size = json["size"];
    _format = json["format"];
    _language = json["language"];
    _type = json["type"];
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["path"] = _path;
    map["size"] = _size;
    map["format"] = _format;
    map["language"] = _language;
    map["type"] = _type;
    return map;
  }
}

class Score {
  double? _score;
  int? _votes;

  double? get score => _score;
  int? get votes => _votes;

  Score({double? score, int? votes}) {
    _score = score;
    _votes = votes;
  }

  Score.fromJson(dynamic json) {
    _score = json["score"] != null ? json["score"].toDouble() : 0;
    _votes = json["votes"];
  }

  Map<String, dynamic> toJson() {
    return {"score": _score, "votes": _votes};
  }
}

class Releases {
  List<Publishers>? _publishers;
  List<Tosec>? _files;

  List<Publishers>? get publishers => _publishers;
  List<Tosec>? get files => _files;

  Releases.fromJson(dynamic json) {
    if (json["publishers"] != null) {
      _publishers = [];
      json["publishers"].forEach((v) {
        _publishers!.add(Publishers.fromJson(v));
      });
    }
    if (json["files"] != null) {
      _files = [];
      json["files"].forEach((v) {
        _files!.add(Tosec.fromJson(v));
      });
    }
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    if (_publishers != null) {
      map["publishers"] = _publishers!.map((v) => v.toJson()).toList();
    }
    if (_files != null) {
      map["files"] = _files!.map((v) => v.toJson()).toList();
    }
    return map;
  }
}

class Total {
  int? _value;
  String? _relation;

  int? get value => _value;
  String? get relation => _relation;

  Total.fromJson(dynamic json) {
    _value = json["value"];
    _relation = json["relation"];
  }

  Map<String, dynamic> toJson() {
    return {"value": _value, "relation": _relation};
  }
}

class Shards {
  int? _total;
  int? _successful;
  int? _skipped;
  int? _failed;

  int? get total => _total;
  int? get successful => _successful;
  int? get skipped => _skipped;
  int? get failed => _failed;

  Shards.fromJson(dynamic json) {
    _total = json["total"];
    _successful = json["successful"];
    _skipped = json["skipped"];
    _failed = json["failed"];
  }

  Map<String, dynamic> toJson() {
    return {
      "total": _total,
      "successful": _successful,
      "skipped": _skipped,
      "failed": _failed
    };
  }
}
