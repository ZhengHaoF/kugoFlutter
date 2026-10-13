#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

// Windows media card / taskbar source name resolution for unpackaged Win32.
//
// SMTC shows the app title from the process AppUserModelID looked up against a
// Start Menu shortcut. Without both, Win11 renders「未知应用」.
void ApplyAppUserModelId();

// Create or refresh our own Start Menu shortcut carrying AUMID + display name
// and the icon from the CURRENT Debug/Profile/Release bundle.
void EnsureStartMenuShortcut();

// One-time cleanup of the pre-rename kugo.lnk shortcut (same AUMID, old name).
void RemoveLegacyShortcut();

#endif  // RUNNER_APP_IDENTITY_H_
