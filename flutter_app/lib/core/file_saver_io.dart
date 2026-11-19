// Lưu tệp báo cáo Word (.docx) & PDF (.pdf) trực tiếp trên Windows và Android
import 'dart:io';
import 'dart:typed_data';

Future<String> saveBinaryFile(String fileName, Uint8List bytes, String mimeType) async {
  Directory targetDir;
  if (Platform.isWindows) {
    final userHome = Platform.environment['USERPROFILE'] ?? Directory.current.path;
    final docs = Directory('$userHome\\Documents\\CALFEM_PhiTuyen_BaoCao');
    if (!await docs.exists()) {
      await docs.create(recursive: true);
    }
    targetDir = docs;
  } else if (Platform.isAndroid) {
    // Lưu trực tiếp vào thư mục Download trên Xiaomi Pad 8 Pro / Xiaomi 13T Pro
    final dl = Directory('/storage/emulated/0/Download/CALFEM_PhiTuyen');
    try {
      if (!await dl.exists()) {
        await dl.create(recursive: true);
      }
      targetDir = dl;
    } catch (_) {
      targetDir = Directory.systemTemp;
    }
  } else {
    targetDir = Directory.systemTemp;
  }

  final sep = Platform.pathSeparator;
  final file = File('${targetDir.path}$sep$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
