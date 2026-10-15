#pragma once

// Minimal Active Template Library (ATL) compatibility header for environments
// without the optional Visual Studio "C++ ATL" component installed.
// Provides the exact CA2W and CW2A string conversions required by
// flutter_secure_storage_windows.

#include <windows.h>
#include <string>
#include <vector>

struct CA2W {
  std::vector<wchar_t> _w;
  LPWSTR m_psz;

  CA2W(const char* s) : m_psz(nullptr) {
    if (!s) return;
    int len = ::MultiByteToWideChar(CP_ACP, 0, s, -1, nullptr, 0);
    if (len > 0) {
      _w.resize(len);
      ::MultiByteToWideChar(CP_ACP, 0, s, -1, _w.data(), len);
      m_psz = _w.data();
    }
  }

  operator LPCWSTR() const { return m_psz; }
  operator LPWSTR() { return m_psz; }
};

struct CW2A {
  std::vector<char> _s;
  LPSTR m_psz;

  CW2A(const wchar_t* ws) : m_psz(nullptr) {
    if (!ws) return;
    int len = ::WideCharToMultiByte(CP_ACP, 0, ws, -1, nullptr, 0, nullptr, nullptr);
    if (len > 0) {
      _s.resize(len);
      ::WideCharToMultiByte(CP_ACP, 0, ws, -1, _s.data(), len, nullptr, nullptr);
      m_psz = _s.data();
    }
  }

  operator std::string() const { return m_psz ? std::string(m_psz) : std::string(); }
  operator LPCSTR() const { return m_psz; }
  operator LPSTR() { return m_psz; }
};
