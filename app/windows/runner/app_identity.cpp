#include "app_identity.h"

#include <shlobj.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>

#include <string>

namespace {

// Must match AudioServiceConfig.androidNotificationChannelId (SMTC AppMediaId).
constexpr wchar_t kAppUserModelId[] = L"com.kugo.player";
constexpr wchar_t kShortcutName[] = L"kugo.lnk";
constexpr wchar_t kAppDisplayName[] = L"kugo";

std::wstring ExePath() {
  wchar_t buffer[MAX_PATH]{};
  ::GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  return buffer;
}

std::wstring StartMenuShortcutPath() {
  wchar_t programs[MAX_PATH]{};
  if (FAILED(::SHGetFolderPathW(nullptr, CSIDL_PROGRAMS, nullptr,
                                SHGFP_TYPE_CURRENT, programs))) {
    return {};
  }
  return std::wstring(programs) + L"\\" + kShortcutName;
}

}  // namespace

void ApplyAppUserModelId() {
  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);
}

void EnsureStartMenuShortcut() {
  const std::wstring link_path = StartMenuShortcutPath();
  if (link_path.empty()) return;
  if (::GetFileAttributesW(link_path.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return;
  }

  const std::wstring exe = ExePath();

  IShellLinkW* link = nullptr;
  HRESULT hr =
      ::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&link));
  if (FAILED(hr) || !link) return;

  link->SetPath(exe.c_str());
  link->SetWorkingDirectory(exe.substr(0, exe.find_last_of(L'\\')).c_str());
  link->SetIconLocation(exe.c_str(), 0);
  link->SetDescription(kAppDisplayName);

  // AUMID on the shortcut is what Windows media card / taskbar resolve the
  // friendly name from. Process AUMID alone is not enough for unpackaged apps.
  IPropertyStore* store = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&store))) && store) {
    PROPVARIANT pv;
    if (SUCCEEDED(::InitPropVariantFromString(kAppUserModelId, &pv))) {
      store->SetValue(PKEY_AppUserModel_ID, pv);
      store->Commit();
      ::PropVariantClear(&pv);
    }
    store->Release();
  }

  IPersistFile* persist = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&persist))) && persist) {
    persist->Save(link_path.c_str(), TRUE);
    persist->Release();
  }
  link->Release();
}
