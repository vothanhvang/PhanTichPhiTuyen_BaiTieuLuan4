// Lưu tệp báo cáo Word (.docx) & PDF (.pdf) kèm HỘP THOẠI CHỌN NƠI LƯU
// chuẩn hệ điều hành trên cả Windows (Win32 GetSaveFileNameW) & Android (SAF)!
import 'dart:io';
import 'package:flutter/services.dart';

const MethodChannel _fileDialogChannel = MethodChannel('calfem.native/file_dialog');

Future<String?> saveBinaryFile(String fileName, Uint8List bytes, String mimeType) async {
  final dotIdx = fileName.lastIndexOf('.');
  final ext = (dotIdx >= 0 && dotIdx < fileName.length - 1)
      ? fileName.substring(dotIdx + 1).toLowerCase()
      : 'pdf';

  if (Platform.isWindows || Platform.isAndroid) {
    try {
      // Hiện hộp thoại "Save As" bản địa của Windows / Android để người dùng chọn thư mục & tên tệp
      final chosen = await _fileDialogChannel.invokeMethod<String>('saveFile', {
        'fileName': fileName,
        'ext': ext,
        'mimeType': mimeType,
        'bytes': bytes,
      });
      // chosen == null nghĩa là người dùng bấm Hủy (Cancel)
      return chosen;
    } on MissingPluginException {
      // Fallback duy nhất khi chạy trong môi trường unit test không có native channel
    }
  }

  // Fallback an toàn cho các nền tảng khác
  Directory targetDir;
  if (Platform.isWindows) {
    final userHome = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    targetDir = Directory('$userHome\\Documents\\CALFEM_PhiTuyen_BaoCao');
  } else if (Platform.isAndroid) {
    targetDir = Directory('/storage/emulated/0/Download/CALFEM_PhiTuyen');
  } else {
    targetDir = Directory.systemTemp;
  }
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }
  final file = File('${targetDir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
