# CopyAmigo EXE Build Instructions

## 🚀 Quick Build

**For most users - just run this:**
```powershell
.\Build-CopyAmigo.ps1
```

That's it! You'll get `CopyAmigo.exe` ready to distribute.

---

## 📋 Detailed Instructions

### Prerequisites
- Windows 10/11
- PowerShell 5.1+ (built into Windows)
- Internet connection (for first-time setup)

### Build Process

1. **Open PowerShell** in the CopyAmigo directory
2. **Run the build script:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File "Build-CopyAmigo.ps1"
   ```
3. **Wait for completion** (usually 30-60 seconds)
4. **Find your exe:** `CopyAmigo.exe` will be created in the same directory

### What the Build Script Does

1. ✅ **Installs PS2EXE** (if not already installed)
2. ✅ **Validates source** (checks CopyAmigo.ps1 exists)
3. ✅ **Converts to EXE** (embeds PowerShell code)
4. ✅ **Sets metadata** (version, description, etc.)
5. ✅ **Creates standalone executable** (no dependencies needed)

---

## 📦 Distribution

### What You Get
- **File:** `CopyAmigo.exe` (~200KB)
- **Dependencies:** None (everything embedded)
- **Requirements:** Windows 10/11 only

### Distribution Options

#### Option 1: Simple Copy
Just copy `CopyAmigo.exe` to any Windows machine and double-click to run.

#### Option 2: Professional Package
Create a folder with:
```
CopyAmigo-v10.0/
├── CopyAmigo.exe          # Main executable
├── README.txt             # User guide
└── BUILD-INSTRUCTIONS.md  # Build instructions (optional)
```

#### Option 3: Installer (Advanced)
Use tools like Inno Setup or NSIS to create a professional installer.

---

## 🛡️ Security Notes

### Windows Defender Warning
**Optimized build:** The current build uses security-optimized parameters to minimize warnings.

**If warnings still appear:**
```
"Windows protected your PC"
Microsoft Defender SmartScreen prevented an unrecognized app from starting.
```

**Solution for users:**
1. Click **"More info"**
2. Click **"Run anyway"**

**Why this happens:**
- PS2EXE creates unsigned executables
- Windows treats unsigned files as potentially unsafe
- Our optimized build reduces but may not eliminate all warnings

**Optimization features:**
- Professional metadata (company, product, copyright)
- No admin privileges required
- DPI awareness for modern displays
- Long path support
- Credential GUI integration

### For Enterprise Deployment
Consider **code signing** the executable:
1. Get a code signing certificate
2. Use `signtool.exe` to sign `CopyAmigo.exe`
3. Signed executables won't trigger warnings

---

## 🔧 Troubleshooting

### "PS2EXE module not found"
**Solution:** The build script will automatically install it. If it fails:
```powershell
Install-Module -Name ps2exe -Force -Scope CurrentUser
```

### "Execution policy" error
**Solution:** Run PowerShell as Administrator and set policy:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "CopyAmigo.ps1 not found"
**Solution:** Make sure you're running the build script from the same directory as `CopyAmigo.ps1`

### EXE won't run on target machine
**Possible causes:**
- Very old Windows version (pre-Windows 10)
- Antivirus blocking execution
- Corrupted download

**Solutions:**
- Ensure Windows 10/11
- Add antivirus exception
- Re-download/rebuild

---

## 🔄 Rebuilding

### When to Rebuild
- After any changes to `CopyAmigo.ps1`
- To update version numbers
- To add/change metadata

### Quick Rebuild
```powershell
.\Build-CopyAmigo.ps1
```
The script will overwrite the existing `CopyAmigo.exe`.

---

## 📊 Technical Details

### PS2EXE Parameters Used
```powershell
ps2exe -inputFile CopyAmigo.ps1 -outputFile CopyAmigo.exe -noConsole -title "CopyAmigo v8.1" -description "Professional Survey Data Copy Tool" -company "CopyAmigo" -product "CopyAmigo" -copyright "2024 CopyAmigo" -version "8.1.0.0"
```

### File Properties
- **Size:** ~200KB (compressed PowerShell + .NET runtime)
- **Type:** Windows PE executable
- **Dependencies:** None (self-contained)
- **Architecture:** x64/x86 compatible

### What's Embedded
- Complete PowerShell script
- Windows Forms GUI code
- All functions and variables
- Minimal .NET runtime components

---

## ✅ Success Checklist

After building, verify:
- [ ] `CopyAmigo.exe` exists and is ~200KB
- [ ] Double-clicking launches the GUI
- [ ] All 4 copy modes are visible
- [ ] Browse button works
- [ ] No console window appears (GUI-only)

---

*CopyAmigo v10.0 - Build system powered by PS2EXE - converts PowerShell scripts to standalone executables*
