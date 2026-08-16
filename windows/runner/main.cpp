#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // Dock the window to the right edge of the primary monitor's work area,
  // sized like a phone: full height, narrow portrait width.
  //
  // |origin| and |size| are logical values; Win32Window::Create scales them
  // back to physical pixels using the monitor DPI.
  HMONITOR monitor = ::MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  ::GetMonitorInfo(monitor, &monitor_info);
  UINT dpi = ::FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi > 0 ? dpi / 96.0 : 1.0;

  int work_width = monitor_info.rcWork.right - monitor_info.rcWork.left;
  int work_height = monitor_info.rcWork.bottom - monitor_info.rcWork.top;
  int window_width = std::min(work_height * 9 / 16, work_width / 2);

  Win32Window::Point origin(
      static_cast<unsigned int>(
          (monitor_info.rcWork.right - window_width) / scale_factor),
      static_cast<unsigned int>(monitor_info.rcWork.top / scale_factor));
  Win32Window::Size size(
      static_cast<unsigned int>(window_width / scale_factor),
      static_cast<unsigned int>(work_height / scale_factor));
  if (!window.Create(L"fluidtext", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
