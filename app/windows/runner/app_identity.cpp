#include "app_identity.h"

#include <shlobj.h>
#include <shobjidl.h>
#include <propkey.h>
#include <propvarutil.h>

#include <string>
#include <cwchar>

namespace {

// Must match AudioServiceConfig.androidNotificationChannelId (SMTC AppMediaId).
constexpr wchar_t kAppUserModelId[] = L"com.kugo.player";
constexpr wchar_t kShortcutName[] = L"kugo.lnk";
constexpr wchar_t kAppDisplayName[] = L"泛音";

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
  const std::wstring exe = ExePath();

  IShellLinkW* link = nullptr;
  HRESULT hr =
      ::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&link));
  if (FAILED(hr) || !link) return;

  IPersistFile* persist = nullptr;
  if (FAILED(link->QueryInterface(IID_PPV_ARGS(&persist))) || !persist) {
    link->Release();
    return;
  }
  const bool exists =
      ::GetFileAttributesW(link_path.c_str()) != INVALID_FILE_ATTRIBUTES;
  if (exists) {
    // Refresh only a shortcut carrying OUR identity; never replace a user's
    // unrelated shortcut merely because it happens to be named kugo.lnk.
    if (FAILED(persist->Load(link_path.c_str(), STGM_READ))) {
      persist->Release();
      link->Release();
      return;
    }
    IPropertyStore* existing_store = nullptr;
    bool owned = false;
    if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&existing_store))) &&
        existing_store) {
      PROPVARIANT identity;
      ::PropVariantInit(&identity);
      if (SUCCEEDED(existing_store->GetValue(PKEY_AppUserModel_ID, &identity)) &&
          identity.vt == VT_LPWSTR && identity.pwszVal) {
        owned = std::wcscmp(identity.pwszVal, kAppUserModelId) == 0;
      }
      ::PropVariantClear(&identity);
      existing_store->Release();
    }
    if (!owned) {
      persist->Release();
      link->Release();
      return;
    }
  }

  const std::wstring directory = exe.substr(0, exe.find_last_of(L'\\'));
  const std::wstring bundled_icon =
      directory + L"\\data\\flutter_assets\\assets\\app_icon.ico";
  const std::wstring icon =
      ::GetFileAttributesW(bundled_icon.c_str()) != INVALID_FILE_ATTRIBUTES
          ? bundled_icon
          : exe;
  link->SetPath(exe.c_str());
  link->SetWorkingDirectory(directory.c_str());
  link->SetIconLocation(icon.c_str(), 0);
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

  if (SUCCEEDED(persist->Save(link_path.c_str(), TRUE))) {
    // Narrow invalidation: do not clear the user's global Explorer icon cache.
    ::SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, icon.c_str(), nullptr);
    ::SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, link_path.c_str(), nullptr);
  }
  persist->Release();
  link->Release();
}
