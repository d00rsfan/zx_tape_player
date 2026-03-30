import 'items_dto.dart';

class ItemDto {
  String? _index;
  String? _type;
  dynamic _id;
  int? _version;
  int? _seqNo;
  int? _primaryTerm;
  bool? _found;
  Source? _source;

  String? get index => _index;
  String? get type => _type;
  dynamic get id => _id;
  int? get version => _version;
  int? get seqNo => _seqNo;
  int? get primaryTerm => _primaryTerm;
  bool? get found => _found;
  Source? get source => _source;

  ItemDto(
      {String? index,
      String? type,
      dynamic id,
      int? version,
      int? seqNo,
      int? primaryTerm,
      bool? found,
      Source? source}) {
    _index = index;
    _type = type;
    _id = id;
    _version = version;
    _seqNo = seqNo;
    _primaryTerm = primaryTerm;
    _found = found;
    _source = source;
  }

  ItemDto.fromJson(dynamic json) {
    _index = json["_index"];
    _type = json["_type"];
    _id = json["_id"];
    _version = json["_version"];
    _seqNo = json["_seq_no"];
    _primaryTerm = json["_primary_term"];
    _found = json["found"];
    _source = json["_source"] != null ? Source.fromJson(json["_source"]) : null;
  }

  Map<String, dynamic> toJson() {
    var map = <String, dynamic>{};
    map["_index"] = _index;
    map["_type"] = _type;
    map["_id"] = _id;
    map["_version"] = _version;
    map["_seq_no"] = _seqNo;
    map["_primary_term"] = _primaryTerm;
    map["found"] = _found;
    if (_source != null) {
      map["_source"] = _source!.toJson();
    }
    return map;
  }
}
