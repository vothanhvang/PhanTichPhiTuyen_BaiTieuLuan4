// Lưu tệp báo cáo Word (.docx) & PDF (.pdf) trên trình duyệt Web:
// Ưu tiên mở hộp thoại "Save As" chọn thư mục bằng File System Access API
// (Chrome / Edge Desktop), tự động fallback sang tải xuống trình duyệt nếu không hỗ trợ.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

@JS('showSaveFilePicker')
external JSPromise<JSObject> _showSaveFilePicker(JSObject options);

Future<String?> saveBinaryFile(String fileName, Uint8List bytes, String mimeType) async {
  // 1. Thử mở hộp thoại chọn nơi lưu chuẩn OS trên Chrome / Edge
  if (web.window.hasProperty('showSaveFilePicker'.toJS).toDart) {
    try {
      final dotIdx = fileName.lastIndexOf('.');
      final ext = (dotIdx >= 0) ? fileName.substring(dotIdx).toLowerCase() : '.pdf';
      final desc = ext == '.docx' ? 'Microsoft Word Document' : 'PDF Document';

      final acceptMap = JSObject();
      acceptMap.setProperty(mimeType.toJS, <JSString>[ext.toJS].toJS);
      final typeEntry = JSObject();
      typeEntry.setProperty('description'.toJS, desc.toJS);
      typeEntry.setProperty('accept'.toJS, acceptMap);

      final opts = JSObject();
      opts.setProperty('suggestedName'.toJS, fileName.toJS);
      opts.setProperty('types'.toJS, <JSObject>[typeEntry].toJS);

      final handle = await _showSaveFilePicker(opts).toDart;
      final createWritablePromise = handle.callMethod<JSPromise<JSObject>>('createWritable'.toJS);
      final writable = await createWritablePromise.toDart;
      final blobParts = <web.BlobPart>[bytes.toJS].toJS;
      final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
      await writable.callMethod<JSPromise<JSAny?>>('write'.toJS, blob).toDart;
      await writable.callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;

      final savedName = (handle.getProperty('name'.toJS) as JSString?)?.toDart ?? fileName;
      return 'Đã lưu tại vị trí bạn chọn: $savedName';
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('AbortError') || msg.contains('aborted')) {
        return null; // Người dùng bấm Cancel
      }
      // Fallback xuống tải xuống trình duyệt bên dưới nếu API bị chặn bởi iframe/chính sách
    }
  }

  // 2. Fallback chuẩn mọi trình duyệt (Firefox, Safari, trình duyệt di động)
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
