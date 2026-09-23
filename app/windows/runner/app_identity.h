#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

// Windows media card / taskbar source name resolution for unpackaged Win32.
//
// SMTC shows the app title from the process AppUserModelID looked up against a
// Start Menu shortcut. Without both, Win11 renders「未知应用」.
void ApplyAppUserModelId();

// Create the Start Menu shortcut carrying our AUMID + display name if missing.
void EnsureStartMenuShortcut();

#endif  // RUNNER_APP_IDENTITY_H_
