#include "flutter_window.h"

#include <commctrl.h>
#include <commdlg.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kNoA11yCrashSubclassId = 4201;

// Prevent Flutter 3.50 Windows engine null-dereference crash (0xc0000005 /
// 0xc000041d) inside AccessibilityBridge::CreateRemoveReparentedNodesUpdate
// (accessibility_bridge.cc:229) when UI Automation queries WM_GETOBJECT while
// dropdowns or dynamic routes reparent semantics nodes.
LRESULT CALLBACK FlutterViewSafeSubclassProc(HWND hwnd,
                                             UINT message,
                                             WPARAM wparam,
                                             LPARAM lparam,
                                             UINT_PTR /*subclass_id*/,
                                             DWORD_PTR /*ref_data*/) {
  if (message == WM_GETOBJECT) {
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  int len = MultiByteToWideChar(CP_UTF8, 0, s.c_str(),
                                static_cast<int>(s.size()), nullptr, 0);
  if (len <= 0) return L"";
  std::wstring out(static_cast<size_t>(len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                      out.data(), len);
  return out;
}

std::string WideToUtf8(const std::wstring& s) {
  if (s.empty()) return "";
  int len = WideCharToMultiByte(CP_UTF8, 0, s.c_str(),
                                static_cast<int>(s.size()), nullptr, 0,
                                nullptr, nullptr);
  if (len <= 0) return "";
  std::string out(static_cast<size_t>(len), '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()),
                      out.data(), len, nullptr, nullptr);
  return out;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Đăng ký kênh hộp thoại "Lưu tệp" (Save As) chuẩn Win32 cho nút Xuất Word / PDF
  file_dialog_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "calfem.native/file_dialog",
          &flutter::StandardMethodCodec::GetInstance());
  file_dialog_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "saveFile") {
          result->NotImplemented();
          return;
        }
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (!args) {
          result->Error("BAD_ARGS", "Thiếu tham số lưu tệp.");
          return;
        }

        std::string file_name = "BaoCao_CALFEM.pdf";
        std::string ext = "pdf";
        std::vector<uint8_t> bytes;

        auto it_name = args->find(flutter::EncodableValue("fileName"));
        if (it_name != args->end()) {
          if (const auto* s = std::get_if<std::string>(&it_name->second)) {
            file_name = *s;
          }
        }
        auto it_ext = args->find(flutter::EncodableValue("ext"));
        if (it_ext != args->end()) {
          if (const auto* s = std::get_if<std::string>(&it_ext->second)) {
            ext = *s;
          }
        }
        auto it_bytes = args->find(flutter::EncodableValue("bytes"));
        if (it_bytes != args->end()) {
          if (const auto* b =
                  std::get_if<std::vector<uint8_t>>(&it_bytes->second)) {
            bytes = *b;
          }
        }

        wchar_t szFile[MAX_PATH * 4] = {};
        std::wstring wname = Utf8ToWide(file_name);
        if (wname.size() < MAX_PATH * 4 - 1) {
          wcsncpy_s(szFile, wname.c_str(), _TRUNCATE);
        }

        std::wstring wext = Utf8ToWide(ext);
        std::wstring filter;
        if (ext == "docx") {
          filter.append(L"Microsoft Word (*.docx)");
          filter.push_back(L'\0');
          filter.append(L"*.docx");
          filter.push_back(L'\0');
        } else if (ext == "pdf") {
          filter.append(L"PDF Document (*.pdf)");
          filter.push_back(L'\0');
          filter.append(L"*.pdf");
          filter.push_back(L'\0');
        }
        filter.append(L"T\x1EA5t c\x1EA3 t\x1EC7p (*.*)");
        filter.push_back(L'\0');
        filter.append(L"*.*");
        filter.push_back(L'\0');
        filter.push_back(L'\0');

        OPENFILENAMEW ofn{};
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = GetHandle();
        ofn.lpstrFilter = filter.c_str();
        ofn.nFilterIndex = 1;
        ofn.lpstrFile = szFile;
        ofn.nMaxFile = static_cast<DWORD>(MAX_PATH * 4);
        ofn.lpstrDefExt = wext.c_str();
        ofn.lpstrTitle =
            L"Ch\x1ECDn n\x01A1i l\x01B0u b\x00E1o c\x00E1o CALFEM";
        ofn.Flags =
            OFN_EXPLORER | OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST |
            OFN_NOCHANGEDIR;

        if (!GetSaveFileNameW(&ofn)) {
          // Người dùng bấm Hủy (Cancel)
          result->Success(flutter::EncodableValue());
          return;
        }

        HANDLE hFile = CreateFileW(szFile, GENERIC_WRITE, 0, nullptr,
                                   CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                                   nullptr);
        if (hFile == INVALID_HANDLE_VALUE) {
          result->Error("IO_ERROR", "Không thể mở tệp để ghi tại vị trí đã chọn.");
          return;
        }
        DWORD written = 0;
        BOOL ok = TRUE;
        if (!bytes.empty()) {
          ok = WriteFile(hFile, bytes.data(),
                         static_cast<DWORD>(bytes.size()), &written, nullptr);
        }
        CloseHandle(hFile);
        if (!ok || written != static_cast<DWORD>(bytes.size())) {
          result->Error("IO_ERROR", "Ghi dữ liệu báo cáo thất bại.");
          return;
        }

        result->Success(flutter::EncodableValue(WideToUtf8(std::wstring(szFile))));
      });

  flutter_view_hwnd_ = flutter_controller_->view()->GetNativeWindow();
  if (flutter_view_hwnd_ != nullptr) {
    SetWindowSubclass(flutter_view_hwnd_, FlutterViewSafeSubclassProc,
                      kNoA11yCrashSubclassId, 0);
  }
  SetChildContent(flutter_view_hwnd_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  file_dialog_channel_.reset();
  if (flutter_view_hwnd_ != nullptr) {
    RemoveWindowSubclass(flutter_view_hwnd_, FlutterViewSafeSubclassProc,
                         kNoA11yCrashSubclassId);
    flutter_view_hwnd_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_GETOBJECT) {
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
