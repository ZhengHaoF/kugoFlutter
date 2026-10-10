/// 云盘上传文件选择与文件名解析。
library;

import 'package:file_picker/file_picker.dart';

/// 与 EchoMusic `CLOUD_UPLOAD_EXTENSIONS` 对齐：本地可播格式 − {alac,webm,wv} + {amr}。
const kCloudUploadExtensions = <String>[
  'mp3',
  'flac',
  'wav',
  'aac',
  'm4a',
  'ape',
  'ogg',
  'wma',
  'amr',
];

/// 单文件上限（与上游 express.raw limit 一致）。
const kCloudUploadMaxBytes = 100 * 1024 * 1024;

class CloudUploadPick {
  const CloudUploadPick({
    required this.name,
    required this.bytes,
    required this.extension,
    this.title = '',
    this.artist = '',
  });

  final String name;
  final List<int> bytes;
  final String extension;

  /// 去扩展名后的展示名。
  final String title;
  final String artist;
}

/// 从文件名解析 `Artist - Title` / `Title`。
({String title, String artist}) parseCloudFileName(String fileName) {
  var base = fileName.trim();
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.trim();
  if (base.isEmpty) return (title: '未知歌曲', artist: '');

  // EchoMusic：`A - B` 取前半为歌手、后半为歌名。
  final sep = base.indexOf(' - ');
  if (sep > 0 && sep < base.length - 3) {
    return (
      title: base.substring(sep + 3).trim(),
      artist: base.substring(0, sep).trim(),
    );
  }
  return (title: base, artist: '');
}

bool isCloudUploadExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  final ext = name.substring(dot + 1).toLowerCase();
  return kCloudUploadExtensions.contains(ext);
}

/// 打开系统文件选择器，过滤音频扩展名与超限文件。
///
/// 取消返回空列表；超限/非法扩展名写入 [errors]。
Future<List<CloudUploadPick>> pickCloudUploadFiles({
  List<String>? errors,
  Future<FilePickerResult?> Function()? picker,
}) async {
  FilePickerResult? result;
  try {
    result =
        await (picker?.call() ??
            FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: kCloudUploadExtensions,
              allowMultiple: true,
              withData: true,
            ));
  } catch (_) {
    errors?.add(
      '无法打开文件选择器。Linux 请安装 zenity、kdialog 或 qarma，'
      '并确认当前桌面会话可访问文件对话框。',
    );
    return const [];
  }
  if (result == null) return const [];

  final out = <CloudUploadPick>[];
  for (final file in result.files) {
    final name = file.name;
    if (!isCloudUploadExtension(name)) {
      errors?.add('$name: 不是支持的音频文件');
      continue;
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      errors?.add('$name: 读取失败');
      continue;
    }
    if (bytes.length > kCloudUploadMaxBytes) {
      errors?.add('$name: 超过 100MB 限制');
      continue;
    }
    final parsed = parseCloudFileName(name);
    final dot = name.lastIndexOf('.');
    out.add(
      CloudUploadPick(
        name: name,
        bytes: bytes,
        extension: dot > 0 ? name.substring(dot + 1).toLowerCase() : 'mp3',
        title: parsed.title,
        artist: parsed.artist,
      ),
    );
  }
  return out;
}
