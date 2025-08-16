# CopyAmigo v10.0 - Visual Guide

**Professional survey data copy tool with 4 specialized workflows**

---

## 🎯 What CopyAmigo Does

CopyAmigo copies survey project data intelligently. Pick a copy mode, choose your destination, click Start Copy. Each mode copies different folders based on what you need.

**Key Features:**
- ✅ **Smart Progress**: Updates every 5% with speed and time remaining
- ✅ **Auto-Optimization**: Detects your hardware and optimizes copy speed
- ✅ **Safe Copying**: Uses Windows Robocopy with error handling
- ✅ **No Overwrites**: Automatically skips existing files to preserve your data
- ✅ **Easy Selection**: Clear descriptions for each copy mode

---

## 📁 The 4 Copy Modes Explained

### 1️⃣ **Raw Data Processing**
*"Everything needed to process a raw dataset"*

**What it copies:**
```
📂 Source Project/
├── 📂 Control/                    ✅ COPIES EVERYTHING
├── 📂 Planning/
│   ├── 📂 Boundary/               ✅ COPIES EVERYTHING  
│   ├── 📂 Work Orders/            ✅ COPIES EVERYTHING
│   └── 📂 Other folders/          ❌ SKIPPED
├── 📂 Raw Data/                   ✅ COPIES EVERYTHING
└── 📂 Other folders/              ❌ SKIPPED

📂 Destination/
├── 📂 Control/                    ← All files copied
├── 📂 Planning/
│   ├── 📂 Boundary/               ← All files copied
│   └── 📂 Work Orders/            ← All files copied
└── 📂 Raw Data/                   ← All files copied
```

**Conditions:**
- ✅ Always copies: Control, Planning\Boundary, Planning\Work Orders, Raw Data
- ⚠️ Missing folders are skipped (logged, not failed)
- 📊 Best for: Initial processing, complete raw datasets

---

### 2️⃣ **Terrascan Project Setup**
*"Complete project setup for Terrascan workflows"*

**What it copies:**
```
📂 Source Project/
├── 📂 Control/                    ✅ COPIES EVERYTHING
├── 📂 Deliverable/                ✅ COPIES EVERYTHING
├── 📂 Orthomosaic/
│   ├── 📂 Finished Ortho Photos/  ✅ COPIES EVERYTHING (with validation)
│   └── 📂 Other folders/          ❌ SKIPPED
├── 📂 Planning/
│   ├── 📂 Boundary/               ✅ COPIES EVERYTHING
│   ├── 📂 Work Orders/            ✅ COPIES EVERYTHING
│   └── 📂 Other folders/          ❌ SKIPPED
├── 📂 Tscan/
│   ├── 📂 DGN/                    ✅ COPIES EVERYTHING
│   ├── 📂 Settings/               ✅ COPIES EVERYTHING
│   └── 📂 Other folders/          ❌ SKIPPED
└── 📂 Other folders/              ❌ SKIPPED

📂 Destination/
├── 📂 Control/                    ← All files copied
├── 📂 Deliverable/                ← All files copied
├── 📂 Orthomosaic/
│   └── 📂 Finished Ortho Photos/  ← All files copied
├── 📂 Planning/
│   ├── 📂 Boundary/               ← All files copied
│   └── 📂 Work Orders/            ← All files copied
└── 📂 Tscan/
    ├── 📂 DGN/                    ← All files copied
    └── 📂 Settings/               ← All files copied
```

**Special Conditions:**
- 🔍 **Orthomosaic Validation**: Checks for .jpg, .jpeg, or .ecw files in Finished Ortho Photos
- ⚠️ **Warning**: Shows warning if no JPG/ECW files found (still creates folder structure)
- ⚠️ Missing folders are skipped (logged, not failed)
- 📊 Best for: Complete Terrascan project handoff

---

### 3️⃣ **Orthomosaic Processing**
*"Minimal files needed for orthomosaic creation"*

**What it copies:**
```
📂 Source Project/
├── 📂 Control/                    ✅ COPIES EVERYTHING
├── 📂 Orthomosaic/
│   ├── 📂 Finished Ortho Photos/  ✅ COPIES EVERYTHING
│   └── 📂 Other folders/          ❌ SKIPPED
├── 📂 Raw Data/
│   ├── 📂 YYYYMMDD-HHMMSS/        🔍 SEARCHES FOR cam0/
│   │   ├── 📂 cam0/               ✅ COPIES EVERYTHING
│   │   └── 📂 other folders/      📁 CREATES EMPTY FOLDERS
│   ├── 📂 RECON-*/
│   │   └── 📂 data/
│   │       ├── 📂 cam0/           ✅ COPIES EVERYTHING  
│   │       └── 📂 other folders/  📁 CREATES EMPTY FOLDERS
│   └── 📂 GeoRef/                 ✅ COPIES .dat FILES ONLY
└── 📂 Other folders/              ❌ SKIPPED

📂 Destination/
├── 📂 Control/                    ← All files copied
├── 📂 Orthomosaic/
│   └── 📂 Finished Ortho Photos/  ← All files copied
├── 📂 GeoRef/                     ← Only .dat files copied
└── 📂 Raw Data/
    └── 📂 [timestamp or RECON]/
        ├── 📂 cam0/               ← All files copied
        └── 📂 other folders/      ← Empty folders created
```

**Conditions:**
- 🔍 **cam0 Search**: Looks for cam0/ in timestamp folders (YYYYMMDD-HHMMSS) or RECON-* folders
- 📁 **Structure Preservation**: Creates complete folder structure, but only copies cam0/ contents
- 📄 **GeoRef Filter**: Only copies .dat files from GeoRef folder
- ⚠️ Missing folders are skipped (logged, not failed)
- 📊 Best for: Orthomosaic processing workflows

---

### 4️⃣ **Tscan**
*"Standard project folders plus selected Tscan data"*

**What it copies:**
```
📂 Source Project/
├── 📂 Control/                    ✅ COPIES EVERYTHING
├── 📂 Orthomosaic/
│   ├── 📂 Finished Ortho Photos/  ✅ COPIES EVERYTHING
│   └── 📂 Other folders/          ❌ SKIPPED
├── 📂 Planning/
│   ├── 📂 Boundary/               ✅ COPIES EVERYTHING
│   ├── 📂 Work Orders/            ✅ COPIES EVERYTHING
│   └── 📂 Other folders/          ❌ SKIPPED
├── 📂 Tscan/
│   ├── 📂 DGN/                    ✅ COPIES EVERYTHING
│   ├── 📂 Settings/               ✅ COPIES EVERYTHING
│   ├── 📂 Helicopter/             🎯 USER SELECTS SUBFOLDERS
│   ├── 📂 Mobile/                 🎯 USER SELECTS SUBFOLDERS
│   ├── 📂 Terrestrial/            🎯 USER SELECTS SUBFOLDERS
│   ├── 📂 UAV/                    🎯 USER SELECTS SUBFOLDERS
│   └── 📂 Other folders/          🎯 USER SELECTS SUBFOLDERS
└── 📂 Other folders/              ❌ SKIPPED

📂 Destination/
├── 📂 Control/                    ← All files copied
├── 📂 Orthomosaic/
│   └── 📂 Finished Ortho Photos/  ← All files copied
├── 📂 Planning/
│   ├── 📂 Boundary/               ← All files copied
│   └── 📂 Work Orders/            ← All files copied
├── 📂 Tscan/
│   ├── 📂 DGN/                    ← All files copied
│   ├── 📂 Settings/               ← All files copied
│   └── 📂 [Selected folders]/     ← Only user-selected folders copied
```

**Selection Process:**
1. 🔍 **Scan**: Program scans Tscan/ folder for main folders (Helicopter, Mobile, etc.)
2. 🎯 **Choose**: User selects which main folder to explore
3. 📋 **List**: Program shows subfolders that pass validation
4. ✅ **Select**: User picks specific subfolders to copy

**Validation Conditions:**
- 🔍 **Structure Check**: Subfolder must contain "Laser02 - Ground by line" folder
- 📊 **File Count**: "Laser02 - Ground by line" must have at least 2 files
- ❌ **Invalid folders**: Hidden from selection list
- ⚠️ Missing standard folders are skipped (logged, not failed)
- 📊 Best for: Selective Tscan data extraction

---

## ⚙️ How the Program Works

### 🚀 **Startup Process**
1. **Auto-Detection**: Finds your project folder automatically
2. **Destination Setup**: Suggests C:\Projects\[ProjectName] or lets you browse
3. **Mode Selection**: Choose one of the 4 copy modes above
4. **Validation**: Ensures destination is valid and mode requirements are met

### 🔧 **Copy Process**
1. **System Analysis**: Detects CPU cores, RAM, drive types (SSD/HDD/Network)
2. **Optimization**: Sets optimal Robocopy parameters for your hardware
3. **Folder Analysis**: Scans selected folders for file counts and sizes
4. **Progress Tracking**: Initializes accurate progress system
5. **Parallel Copying**: Uses optimized Robocopy with multiple threads
6. **Progress Updates**: Shows updates every 5% with speed and ETA
7. **Completion**: Shows summary with total files, size, and any warnings

### 📊 **Progress System**
- **Smart Updates**: Only shows progress every 5% (no spam)
- **Accurate Tracking**: Weighted average (60% size, 30% files, 10% operations)
- **Real-Time Metrics**: Transfer speed (MB/s) and estimated time remaining
- **Clean Display**: `15% complete | Files: 310/2069 | Size: 10.4/69.48 GB | Speed: 45.2 MB/s | ETA: 22m 15s`

### 🛡️ **Data Safety**
- **No Overwrites**: CopyAmigo will NEVER overwrite existing files
- **Automatic Skip**: If a file already exists at the destination, it's automatically skipped
- **Preserve Existing**: Your existing files are completely safe and untouched
- **Smart Notification**: Shows you which files were skipped (if any)

---

## 🛠️ System Requirements

**Minimum:**
- Windows 10 or 11
- PowerShell 5.1+
- 4GB RAM
- 10GB free space

**Recommended:**
- 16GB RAM for large projects
- SSD storage for better performance
- Gigabit network for remote copying

---

## 🚀 Quick Start

1. **Download**: Get `CopyAmigo.ps1` and `CopyAmigo.bat`
2. **Run**: Double-click `CopyAmigo.bat` (or run PowerShell script directly)
3. **Select**: Choose your copy mode and destination
4. **Copy**: Click "Start Copy" and watch the progress

---

## 🔧 Technical Details

### **File Operations**
- **Engine**: Windows Robocopy with dynamic optimization
- **Threads**: Auto-detected based on CPU cores and drive types
- **Parameters**: Optimized for SSD-to-SSD, HDD-to-HDD, or network copies
- **Safety**: Preserves timestamps, attributes, and handles long paths

### **Error Handling**
- **Missing Folders**: Skipped and logged (not failed)
- **Permission Issues**: Detailed error messages
- **Network Problems**: Automatic retry logic
- **Cancellation**: Safe operation termination

### **Performance Features**
- **Hardware Detection**: CPU cores, RAM, drive types
- **Dynamic Optimization**: Adjusts threads, retries, buffering
- **Progress Efficiency**: Minimal overhead, accurate tracking
- **Memory Management**: Efficient resource usage

---

## 📋 Troubleshooting

### **Common Issues**

**"Script won't start"**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**"No Tscan folders visible"**
- Check folders contain "Laser02 - Ground by line" subfolder
- Ensure subfolder has at least 2 files

**"Slow copying"**
- Close other applications
- Check available disk space
- Verify network connection

**"Destination not found"**
- Create C:\Projects directory or browse manually
- Check folder permissions

---

*CopyAmigo v10.0 - Optimized for survey and LIDAR project workflows*
