param(
  [Parameter(Mandatory = $true)][string]$Executable,
  [Parameter(Mandatory = $true)][string]$Report
)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot/installer_probe_helpers.ps1"
$exe = (Resolve-Path $Executable).Path
$bundleIcon = Join-Path (Split-Path $exe) "data\flutter_assets\assets\app_icon.ico"
if (-not (Test-Path $bundleIcon)) { throw "Missing bundled runtime app icon" }
$sourceIcon = (Resolve-Path "windows\runner\resources\app_icon.ico").Path
if ((Get-FileHash $bundleIcon).Hash -ne (Get-FileHash $sourceIcon).Hash) {
  throw "Runtime and embedded-source icons differ"
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

public static class OvertoneIconProbe {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern IntPtr LoadLibraryEx(string file, IntPtr reserved, uint flags);
  [DllImport("kernel32.dll")]
  static extern bool FreeLibrary(IntPtr module);
  [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode)]
  static extern IntPtr LoadIconFile(IntPtr module, string path, uint type, int cx, int cy, uint flags);
  [DllImport("user32.dll", EntryPoint = "LoadImageW")]
  static extern IntPtr LoadIconResource(IntPtr module, IntPtr id, uint type, int cx, int cy, uint flags);
  [DllImport("user32.dll")]
  static extern bool DestroyIcon(IntPtr icon);
  [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
  static extern IntPtr SendMessageTimeout(IntPtr window, uint message, IntPtr wparam,
      IntPtr lparam, uint flags, uint timeout, out IntPtr result);
  [StructLayout(LayoutKind.Sequential)]
  struct IconInfo {
    [MarshalAs(UnmanagedType.Bool)] public bool isIcon;
    public uint hotspotX, hotspotY;
    public IntPtr mask, color;
  }
  [StructLayout(LayoutKind.Sequential)]
  struct BitmapData {
    public int type, width, height, stride;
    public ushort planes, bitsPixel;
    public IntPtr bits;
  }
  [StructLayout(LayoutKind.Sequential)]
  struct BitmapInfoHeader {
    public uint size;
    public int width, height;
    public ushort planes, bitCount;
    public uint compression, sizeImage;
    public int xPixelsPerMeter, yPixelsPerMeter;
    public uint colorsUsed, colorsImportant;
  }
  [DllImport("user32.dll")]
  static extern bool GetIconInfo(IntPtr icon, out IconInfo info);
  [DllImport("gdi32.dll", EntryPoint = "GetObjectW")]
  static extern int GetObject(IntPtr bitmap, int size, out BitmapData data);
  [DllImport("gdi32.dll")]
  static extern bool DeleteObject(IntPtr value);
  [DllImport("user32.dll")]
  static extern IntPtr GetDC(IntPtr window);
  [DllImport("user32.dll")]
  static extern int ReleaseDC(IntPtr window, IntPtr dc);
  [DllImport("gdi32.dll")]
  static extern int GetDIBits(IntPtr dc, IntPtr bitmap, uint first, uint lines,
      [Out] byte[] pixels, ref BitmapInfoHeader info, uint usage);

  static string Digest(IntPtr handle) {
    if (handle == IntPtr.Zero) throw new InvalidOperationException("No icon handle");
    IconInfo icon;
    if (!GetIconInfo(handle, out icon)) throw new InvalidOperationException("GetIconInfo failed");
    IntPtr dc = IntPtr.Zero;
    try {
      BitmapData bitmap;
      if (icon.color == IntPtr.Zero ||
          GetObject(icon.color, Marshal.SizeOf(typeof(BitmapData)), out bitmap) == 0) {
        throw new InvalidOperationException("No color icon bitmap");
      }
      BitmapInfoHeader info = new BitmapInfoHeader();
      info.size = (uint)Marshal.SizeOf(typeof(BitmapInfoHeader));
      info.width = bitmap.width;
      info.height = -bitmap.height;
      info.planes = 1;
      info.bitCount = 32;
      byte[] pixels = new byte[bitmap.width * bitmap.height * 4];
      dc = GetDC(IntPtr.Zero);
      if (GetDIBits(dc, icon.color, 0, (uint)bitmap.height, pixels, ref info, 0) != bitmap.height) {
        throw new InvalidOperationException("GetDIBits failed");
      }
      using (SHA256 hash = SHA256.Create()) {
        return bitmap.width + "x" + bitmap.height + ":" +
            BitConverter.ToString(hash.ComputeHash(pixels));
      }
    } finally {
      if (dc != IntPtr.Zero) ReleaseDC(IntPtr.Zero, dc);
      if (icon.mask != IntPtr.Zero) DeleteObject(icon.mask);
      if (icon.color != IntPtr.Zero) DeleteObject(icon.color);
    }
  }

  public static string FileDigest(string file, int size) {
    IntPtr icon = LoadIconFile(IntPtr.Zero, file, 1, size, size, 0x10);
    try { return Digest(icon); } finally { if (icon != IntPtr.Zero) DestroyIcon(icon); }
  }

  public static string EmbeddedDigest(string exe, int size) {
    IntPtr module = LoadLibraryEx(exe, IntPtr.Zero, 0x22);
    if (module == IntPtr.Zero) throw new InvalidOperationException("Cannot load EXE resources");
    IntPtr icon = LoadIconResource(module, new IntPtr(101), 1, size, size, 0);
    try { return Digest(icon); }
    finally {
      if (icon != IntPtr.Zero) DestroyIcon(icon);
      FreeLibrary(module);
    }
  }

  public static string WindowDigest(IntPtr window, bool small) {
    // Explicit WM_GETICON, not the class fallback. The Dart runtime must
    // actually have sent WM_SETICON to this window.
    IntPtr icon;
    if (SendMessageTimeout(window, 0x7f, new IntPtr(small ? 0 : 1),
        IntPtr.Zero, 2, 2000, out icon) == IntPtr.Zero) {
      throw new InvalidOperationException("WM_GETICON timed out");
    }
    return Digest(icon);
  }
}
'@

$expectedBig = [OvertoneIconProbe]::FileDigest($bundleIcon, 32)
$expectedSmall = [OvertoneIconProbe]::FileDigest($bundleIcon, 16)
if ([OvertoneIconProbe]::EmbeddedDigest($exe, 32) -ne $expectedBig) {
  throw "EXE embedded icon does not match approved G runtime icon"
}
$checks = [System.Collections.Generic.List[string]]::new()
$checks.Add("PASS embedded EXE icon matches G")
$process = $null
$primaryFailure = $null
try {
  $process = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
  $ready = $false
  $lastState = "No visible top-level window"
  $deadline = [DateTime]::UtcNow.AddSeconds(90)
  while ([DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
    if ($process.HasExited) { throw "Application exited before icon acceptance: $($process.ExitCode)" }
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { continue }
    try {
      $big = [OvertoneIconProbe]::WindowDigest($process.MainWindowHandle, $false)
      $small = [OvertoneIconProbe]::WindowDigest($process.MainWindowHandle, $true)
      $lastState = "large=$big; small=$small"
      if ($big -eq $expectedBig -and $small -eq $expectedSmall) {
        $ready = $true
        break
      }
    } catch {
      # The native window exists before DesktopShell finishes initialization.
      $lastState = $_.Exception.Message
    }
  }
  if (-not $ready) { throw "Running window did not install G icons. Last state: $lastState" }
  $checks.Add("PASS running window large icon matches G")
  $checks.Add("PASS running window small icon matches G")

  $programs = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
  $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $programs "overtone.lnk"))
  if ($shortcut.TargetPath -ne $exe) { throw "Start Menu shortcut points at an old executable" }
  $iconLocation = $shortcut.IconLocation
  if ($iconLocation -notmatch '^(.*),\s*0$' -or $Matches[1].Trim('"') -ne $bundleIcon) {
    throw "Start Menu shortcut still references an old icon"
  }
  $checks.Add("PASS Start Menu target and icon resolve to current bundle")
  $checks | Set-Content -Path $Report -Encoding utf8
  $checks | ForEach-Object { Write-Host $_ }
} catch {
  $primaryFailure = $_
  throw
} finally {
  try {
    Stop-OvertoneProbeProcess -Process $process
  } catch {
    if ($null -ne $primaryFailure) {
      Write-Warning "Application teardown also failed; preserving the original icon acceptance error: $_"
    } else {
      throw
    }
  }
}
