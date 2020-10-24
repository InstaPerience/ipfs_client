import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:quiver/core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

abstract class Streamable {
  http.ByteStream getByteStream();

  Optional<String> getName();

  List<Streamable> getChildren();

  bool isDirectory();
}

class ByteArrayStream implements Streamable {
  final Uint8List _bytes;
  final Optional<String> _name;

  ByteArrayStream.from(this._bytes, {String name}) : _name  = Optional.fromNullable(name);
  ByteArrayStream.fromString(String content, {String name, Encoding encoding = utf8}) : _bytes = encoding.encode(content), _name = Optional.fromNullable(name);

  @override
  http.ByteStream getByteStream() {
    return http.ByteStream.fromBytes(_bytes);
  }

  @override
  List<Streamable> getChildren() {
    return Iterable.empty();
  }

  @override
  Optional<String> getName() {
    return _name;
  }

  @override
  bool isDirectory() {
    return false;
  }
}

class DirectoryStream implements Streamable {
  final String _directoryName;
  final List<Streamable> _children;

  DirectoryStream(this._directoryName, this._children);

  @override
  http.ByteStream getByteStream() {
    throw Exception('Directory cannot provide a ByteStream');
  }

  @override
  List<Streamable> getChildren() {
    // TODO: implement getChildren
    return _children;
  }

  @override
  Optional<String> getName() {
    // TODO: implement getName
    return Optional.of(_directoryName);
  }

  @override
  bool isDirectory() {
    // TODO: implement isDirectory
    return true;
  }
}

class FileStream implements Streamable {
  final File _file;

  FileStream(this._file);

  FileStream.fromPath(String path) : _file = File(path);

  @override
  http.ByteStream getByteStream() {
    // TODO: implement getByteStream
    return http.ByteStream(_file.openRead());
  }

  @override
  List<Streamable> getChildren() {
    // TODO: implement getChildren
    return Iterable.empty();
  }

  @override
  Optional<String> getName() {
    return Optional.of(p.basename(_file.path));
  }

  @override
  bool isDirectory() {
    return false;
  }
}
