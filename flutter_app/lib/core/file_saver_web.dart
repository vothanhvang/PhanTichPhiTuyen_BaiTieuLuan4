// Tải xuống tệp báo cáo Word (.docx) & PDF (.pdf) trực tiếp trên trình duyệt GitHub Pages Web
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<String> saveBinaryFile(String fileName, Uint8List bytes, String mimeType) async {
  final blobParts = <web.BlobPart>[bytes.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return 'Đã tải xuống trình duyệt: $fileName';
}
