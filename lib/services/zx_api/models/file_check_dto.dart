class FileCheckDto {
  String? _entryId;
  String? _title;
  FileItem? _file;

  String? get entryId => _entryId;
  String? get title => _title;
  FileItem? get file => _file;

  FileCheckDto({String? entryId, String? title, FileItem? file}) {
    _entryId = entryId;
    _title = title;
    _file = file;
  }

  FileCheckDto.fromJson(dynamic json) {
    _entryId = json["entry_id"];
    _title = json["title"];
    var file = json["file"];
    if (file is List && file.isNotEmpty) {
      _file = FileItem.fromJson(file[0]);
    } else if (file is Map) {
      _file = FileItem.fromJson(file);
    }
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["entry_id"] = _entryId;
    map["title"] = _title;
    if (_file != null) {
      map["file"] = _file!.toJson();
    }
    return map;
  }
}

class FileItem {
  String? _filename;
  String? _md5;

  String? get filename => _filename;
  String? get md5 => _md5;

  FileItem({String? filename, String? md5}) {
    _filename = filename;
    _md5 = md5;
  }

  FileItem.fromJson(dynamic json) {
    _filename = json["filename"];
    _md5 = json["md5"];
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["filename"] = _filename;
    map["md5"] = _md5;
    return map;
  }
}
