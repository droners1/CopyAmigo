# CopyAmigo v10.0 - Complete User Guide

**Professional Survey Data Copy Tool - Made Simple for Everyone**

---

## 🎯 What is CopyAmigo?

CopyAmigo is a smart, user-friendly tool that helps you copy survey project data from one location to another. Think of it as a "smart copy machine" that knows exactly what files you need for different types of survey work.

**Why Use CopyAmigo Instead of Regular Copy/Paste?**
- ✅ **Smart Selection**: Automatically picks the right folders for your workflow
- ✅ **No Mistakes**: Won't copy unnecessary files or miss important ones
- ✅ **Fast & Safe**: Uses Windows' best copy tools with progress tracking
- ✅ **Professional**: Designed specifically for survey and LIDAR projects
- ✅ **Easy to Use**: Simple interface that anyone can understand
- ✅ **TScan Optimized**: Special features for TScan data workflows

---

## 🚀 How to Get Started (Super Simple!)

### **Step 1: Run the Program**
- Double-click `CopyAmigo.exe` (that's it!)
- No installation needed - it just works!
- **Note**: This is a standalone executable built with PS2EXE

### **Step 2: Pick Your Project**
- The program automatically finds your current project folder
- Or click "Search Projects" to find a different one
- It will suggest a destination folder for you

### **Step 3: Choose Your Copy Mode**
- Pick one of the 4 copy modes (explained below)
- Each mode copies different folders based on what you need

### **Step 4: Start Copying**
- Click "Start Copy" and watch the progress
- The program shows you exactly what's happening
- When it's done, you'll see a summary

---

## 📁 The 4 Copy Modes - Explained with Visuals

### **Mode 1: Raw Data Processing** 📊
*"I need everything to process raw survey data"*

**What This Mode Does:**
- Copies ALL the essential folders you need to start processing raw survey data
- Perfect for when you're just beginning to work with a new dataset

**What Gets Copied:**
```
📁 Project Root/
├── 📁 Control/                    ← All your control points and survey data
├── 📁 Planning/
│   ├── 📁 Boundary/              ← Your project boundaries and planning files
│   └── 📁 Work Orders/           ← Work orders and project specifications
├── 📁 Raw Data/                  ← All your raw survey data files
│   ├── 📁 cam0/                  ← Camera data from various timestamp folders
│   ├── 📁 GeoRef/                ← Coordinate reference files (.dat files)
│   └── 📁 [Other Data Folders]/  ← Any additional data structures
└── 📁 [Other Project Folders]/   ← Any other folders in your project
```

**When to Use This Mode:**
- Starting a new survey project
- Need to process raw data from scratch
- Want to make sure you have everything before starting work
- Creating a complete backup of your project

**What Happens:**
- Creates a complete copy of your essential project structure
- Skips any folders that don't exist (no errors, just skips them)
- Perfect for initial project setup

---

### **Mode 2: Terrascan Project Setup** 🎯
*"I need everything for a complete Terrascan workflow"*

**What This Mode Does:**
- Copies everything needed for a complete Terrascan project
- Includes special validation for orthomosaic files
- Perfect for handing off projects to Terrascan users

**What Gets Copied:**
```
📁 Project Root/
├── 📁 Control/                    ← All control points and survey data
├── 📁 Deliverable/                ← All deliverable files
├── 📁 Orthomosaic/
│   └── 📁 Finished Ortho Photos/ ← All finished orthophotos
├── 📁 Planning/
│   ├── 📁 Boundary/              ← Project boundaries
│   └── 📁 Work Orders/           ← Work orders
├── 📁 Tscan/
│   ├── 📁 DGN/                   ← All Tscan design files
│   └── 📁 Settings/              ← All Tscan settings and configurations
└── 📁 [Other Project Folders]/   ← Any additional project folders
```

**Special Features:**
- **Smart Validation**: Checks that your orthomosaic folder actually contains photo files
- **Warning System**: Tells you if something looks wrong (but still copies what it can)
- **Complete Setup**: Gives you everything needed for Terrascan work

**When to Use This Mode:**
- Setting up a complete Terrascan project
- Handing off projects to other team members
- Need the full project structure for Terrascan workflows
- Creating comprehensive project archives

---

### **Mode 3: Orthomosaic Processing** 📸
*"I only need the minimum files to create orthomosaics"*

**What This Mode Does:**
- Copies only the essential files needed for orthomosaic creation
- Saves space by not copying unnecessary data
- Creates the exact folder structure you need

**What Gets Copied:**
```
📁 Project Root/
├── 📁 Control/                    ← All control points (needed for accuracy)
├── 📁 Orthomosaic/
│   └── 📁 Finished Ortho Photos/ ← All finished photos
└── 📁 Raw Data/                  ← Only the camera data you need
    ├── 📁 cam0/                  ← Camera data from timestamp folders
    ├── 📁 cam0/                  ← Camera data from RECON folders  
    └── 📁 GeoRef/                ← Only .dat files (coordinate reference)
```

**Smart Features:**
- **Camera Data Search**: Automatically finds and copies camera data from different folder types
- **Structure Preservation**: Creates all the folders you need, even if some are empty
- **File Filtering**: Only copies the specific file types you need for orthomosaic work

**When to Use This Mode:**
- Creating orthomosaics from survey data
- Need to save disk space
- Only want the essential files for photo processing
- Sharing orthomosaic data with clients

---

### **Mode 4: Tscan (Selective Data)** 🎛️
*"I need standard project files plus specific Tscan data"*

**What This Mode Does:**
- Copies all the standard project folders
- **ALWAYS copies the "QC" folder and "macro" subfolder** (automatically)
- Lets you pick and choose which Tscan data to include
- Perfect for when you need flexibility in what gets copied

**What Gets Copied (Standard - Always):**
```
📁 Project Root/
├── 📁 Control/                    ← All control points
├── 📁 Planning/
│   ├── 📁 Boundary/              ← Project boundaries
│   └── 📁 Work Orders/           ← Work orders
├── 📁 QC/                        ← ALWAYS copied (new in v10.0!)
├── 📁 Tscan/
│   ├── 📁 DGN/                   ← All Tscan design files
│   ├── 📁 Settings/              ← All Tscan settings
│   └── 📁 [Main Folder]/         ← Main Tscan data folder
│       └── 📁 macro/             ← ALWAYS copied automatically (new in v10.0!)
└── 📁 [Other Project Folders]/   ← Any additional project folders
```

**What You Choose (Tscan Data):**
```
🎯 Tscan/[Main Folder]/           ← You pick which subfolders
    ├── 📁 [Subfolder 1]/         ← You select from available options
    ├── 📁 [Subfolder 2]/         ← You select from available options
    ├── 📁 [Subfolder 3]/         ← You select from available options
    └── 📁 [Subfolder N]/         ← You select from available options
```

**How the Selection Works:**
1. **Scan**: Program looks through your Tscan main folder
2. **Validate**: Only shows folders that contain valid data
3. **Choose**: You pick which ones you want
4. **Copy**: Only copies the folders you selected

**Smart Validation:**
- Only shows folders that contain valid survey data
- Ensures the data folder has meaningful content
- Hides invalid or empty folders automatically

**New Features in v10.0:**
- **QC Folder**: Always copied automatically (no selection needed)
- **Macro Subfolder**: Always copied automatically from the main Tscan folder
- **Transparent Operation**: These folders are copied without user intervention

**When to Use This Mode:**
- Need flexibility in what Tscan data to copy
- Want to save space by not copying everything
- Need to share specific parts of a project
- Working with Tscan workflows that require QC and macro data

---

## ⚙️ How CopyAmigo Works (Behind the Scenes)

### **The Smart Startup Process**
1. **Auto-Detection**: CopyAmigo automatically finds your current project folder
2. **Smart Destination**: Suggests a logical destination (usually C:\Projects\[ProjectName])
3. **Mode Selection**: You pick which copy mode fits your needs
4. **Validation**: The program checks that everything looks good before starting

### **The Intelligent Copy Process**
1. **System Analysis**: CopyAmigo looks at your computer and figures out the best way to copy files
2. **Hardware Detection**: Identifies your CPU cores, RAM, and drive types (SSD/HDD/Network)
3. **Optimization**: Sets the perfect copy settings for your specific hardware
4. **Folder Scanning**: Counts files and calculates total size for accurate progress tracking
5. **Smart Copying**: Uses Windows' best copy tools with multiple threads for speed
6. **Progress Updates**: Shows you exactly what's happening every step of the way
7. **Completion**: Gives you a detailed summary of what was copied

### **The Progress System (How You Know What's Happening)**
- **Smart Updates**: Only shows progress every 5% (no spam, just important updates)
- **Real-Time Speed**: Shows transfer speed in MB/s (megabytes per second)
- **Time Estimates**: Tells you how long until completion
- **File Counting**: Shows how many files have been processed
- **Size Tracking**: Shows how much data has been transferred

**Example Progress Display:**
```
15% complete | Files: 310/2069 | Size: 10.4/69.48 GB | Speed: 45.2 MB/s | ETA: 22m 15s
```

### **The Safety Features (Your Data is Protected)**
- **No Overwrites**: CopyAmigo will NEVER overwrite existing files
- **Automatic Skip**: If a file already exists, it's automatically skipped
- **Preserve Existing**: Your existing files are completely safe and untouched
- **Smart Notifications**: Shows you which files were skipped (if any)

---

## 🛠️ What Your Computer Needs

### **Minimum Requirements (Will Work on Most Computers)**
- Windows 10 or 11
- 4GB RAM (memory)
- 10GB free disk space
- Any modern hard drive or SSD

### **Recommended (For Best Performance)**
- 16GB RAM (for very large projects)
- SSD storage (faster than regular hard drives)
- Gigabit network connection (for copying over network)

### **What CopyAmigo Automatically Detects**
- **CPU Cores**: How many processing cores your computer has
- **RAM Amount**: How much memory is available
- **Drive Types**: Whether you're using SSD, HDD, or network storage
- **Network Speed**: How fast your network connection is

---

## 🚀 Quick Start Guide (Step by Step)

### **First Time Setup**
1. **Download**: Get `CopyAmigo.exe` from your project folder
2. **Run**: Double-click the file (no installation needed!)
3. **Allow**: If Windows asks, click "Yes" to allow the program to run

### **Running CopyAmigo**
1. **Wait for Startup**: Program will automatically find your project
2. **Check Source**: Verify it found the right project folder
3. **Set Destination**: Choose where you want to copy files to
4. **Pick Mode**: Select the copy mode that fits your needs
5. **Start Copy**: Click "Start Copy" and watch the magic happen!

### **During the Copy Process**
- **Progress Bar**: Shows overall completion percentage
- **Status Updates**: Tells you exactly what's happening
- **Speed Display**: Shows how fast files are copying
- **Time Remaining**: Estimates when the copy will finish
- **File Details**: Shows which file is currently being copied

### **When Copying is Complete**
- **Summary**: Shows total files copied and total size
- **Time Taken**: Shows how long the entire process took
- **Any Warnings**: Tells you if anything unusual happened
- **Success Message**: Confirms everything completed successfully

---

## 🔧 Troubleshooting (Fixing Common Problems)

### **"The program won't start"**
**Solution**: Right-click `CopyAmigo.exe` and select "Run as administrator"

**Why This Happens**: Windows sometimes blocks programs for security reasons

### **"I can't find my project folder"**
**Solution**: Click "Search Projects" and browse to find your folder

**Why This Happens**: The program looks in common locations, but your project might be elsewhere

### **"The copy is very slow"**
**Solutions**:
- Close other programs that might be using the disk
- Check if you have enough free disk space
- If copying over network, check your network connection

**Why This Happens**: Copying speed depends on your hardware and network

### **"Some folders weren't copied"**
**Solutions**:
- Check the status messages for any error details
- Verify you have permission to access those folders
- Make sure the source folders actually exist

**Why This Happens**: Some folders might be missing, empty, or have permission issues

### **"I get an error about PowerShell"**
**Solution**: You don't need PowerShell! Just run `CopyAmigo.exe` directly

**Why This Happens**: The program includes everything it needs to run

---

## 📊 Understanding the Technical Details

### **What CopyAmigo Uses to Copy Files**
- **Engine**: Windows Robocopy (the best file copy tool available)
- **Threads**: Automatically uses the right number based on your CPU
- **Parameters**: Optimized settings for your specific hardware
- **Safety**: Preserves file timestamps, attributes, and handles long file paths

### **How CopyAmigo Optimizes Performance**
- **Drive Detection**: Knows if you're using SSD, HDD, or network storage
- **Thread Optimization**: Uses more threads for faster drives, fewer for slower ones
- **Buffer Sizing**: Adjusts memory usage based on available RAM
- **Network Optimization**: Special settings for network copies

### **Error Handling and Recovery**
- **Missing Folders**: Automatically skipped and logged (doesn't stop the process)
- **Permission Issues**: Clear error messages explaining what went wrong
- **Network Problems**: Automatic retry logic for temporary issues
- **Cancellation**: Safe operation termination if you need to stop

### **Progress Tracking Accuracy**
- **Weighted Calculation**: 60% based on file size, 30% on file count, 10% on operations
- **Real-Time Updates**: Progress updates every 5% with current file information
- **Speed Calculation**: Accurate transfer speed based on actual data copied
- **Time Estimation**: Smart estimates based on current speed and remaining work

---

## 🎯 Advanced Features for Power Users

### **Custom Destination Paths**
- Browse to any folder on your computer or network
- Create new folders during the selection process
- Use network paths (\\server\share\folder)

### **Project Search and Selection**
- Search through multiple project locations
- Browse different project roots
- Switch between projects without restarting

### **Detailed Logging**
- Every operation is logged with timestamps
- Progress updates show exactly what's happening
- Error messages include detailed information for troubleshooting

### **Performance Monitoring**
- Real-time transfer speed display
- Progress percentage with file and size counts
- Estimated time remaining calculations

---

## 📋 Best Practices for Best Results

### **Before Starting a Copy**
1. **Check Disk Space**: Make sure you have enough room for the copy
2. **Close Other Programs**: Especially programs that might be using the disk
3. **Verify Source**: Make sure your source project folder is complete
4. **Choose Destination**: Pick a location that makes sense for your workflow

### **During the Copy Process**
1. **Don't Interrupt**: Let the copy complete without stopping it
2. **Monitor Progress**: Watch for any error messages or warnings
3. **Be Patient**: Large projects can take time, especially over network

### **After Copying is Complete**
1. **Check the Summary**: Review what was copied and any warnings
2. **Verify Files**: Make sure important folders and files are present
3. **Test Access**: Try opening some files to ensure they copied correctly

---

## 🔍 Understanding CopyAmigo's Smart Features

### **Automatic Project Detection**
CopyAmigo is smart enough to:
- Find your current project folder automatically
- Detect common project root locations (H:\Survey\, C:\Projects\, etc.)
- Remember your last used locations
- Handle network and local paths seamlessly

### **Intelligent Mode Selection**
Each copy mode is designed for specific workflows:
- **Raw Data**: Complete datasets for initial processing
- **Terrascan**: Full project setup for Terrascan workflows
- **Orthomosaic**: Minimal files for photo processing
- **Tscan**: Flexible selection for specific data needs with automatic QC and macro copying

### **Smart Progress Tracking**
The progress system:
- Updates only when meaningful changes occur (every 5%)
- Shows real-time transfer speed and time estimates
- Tracks both file count and data size progress
- Provides detailed status updates during operation

### **Automatic Optimization**
CopyAmigo automatically:
- Detects your hardware capabilities
- Chooses optimal copy parameters
- Adjusts thread count based on drive types
- Optimizes for network vs. local copying

---

## 🛠️ For Developers: Building CopyAmigo

### **Prerequisites**
- Windows 10/11 with PowerShell 5.1+
- PS2EXE module installed in user profile

### **Install PS2EXE Module**
```powershell
# Install PS2EXE to user profile
Install-Module -Name PS2EXE -Scope CurrentUser -Force
```

### **Build the Executable**
```powershell
# Build CopyAmigo.exe from CopyAmigo.ps1
Invoke-ps2exe -inputFile CopyAmigo.ps1 -outputFile CopyAmigo.exe -noConsole -noError -title "CopyAmigo" -version "10.0" -company "CopyAmigo" -product "CopyAmigo" -copyright "CopyAmigo 2025"
```

### **Build Parameters Explained**
- `-noConsole`: Creates Windows GUI application (no console window)
- `-noError`: Suppresses error dialogs for cleaner UX
- `-title`: Sets application title
- `-version`: Sets version number
- `-company`: Sets company metadata
- `-product`: Sets product name
- `-copyright`: Sets copyright information

### **Module Location**
PS2EXE should be installed at:
```
C:\Users\[Username]\Documents\WindowsPowerShell\Modules\ps2exe\
```

---

## 📞 Getting Help and Support

### **If Something Goes Wrong**
1. **Check the Status Messages**: CopyAmigo tells you exactly what's happening
2. **Look for Error Details**: Error messages include specific information
3. **Check the Log**: All operations are logged with timestamps
4. **Verify Permissions**: Make sure you can access source and destination folders

### **Common Error Messages and Solutions**
- **"Access Denied"**: Run as administrator or check folder permissions
- **"Path Not Found"**: Verify the folder path exists and is accessible
- **"Insufficient Space"**: Free up disk space or choose different destination
- **"Network Error"**: Check network connection and try again

### **Performance Tips**
- **Use SSD Storage**: Much faster than regular hard drives
- **Close Other Programs**: Free up system resources
- **Check Network Speed**: Faster networks mean faster copying
- **Monitor Disk Space**: Ensure adequate free space

---

## 🎉 What Makes CopyAmigo Special

### **Professional-Grade Features**
- **Survey-Specific**: Designed specifically for survey and LIDAR projects
- **Smart Automation**: Automatically handles complex folder structures
- **Progress Tracking**: Professional-level progress monitoring
- **Error Handling**: Robust error handling and recovery
- **TScan Optimized**: Special features for TScan workflows

### **User-Friendly Design**
- **Simple Interface**: Easy to understand and use
- **Automatic Detection**: Finds your projects automatically
- **Smart Defaults**: Suggests sensible options
- **Clear Feedback**: Always tells you what's happening

### **Performance and Reliability**
- **Hardware Optimization**: Automatically optimized for your computer
- **Safe Operations**: Never overwrites existing files
- **Network Support**: Works with local and network locations
- **Progress Accuracy**: Real-time progress with accurate estimates

### **New in Version 10.0**
- **Automatic QC Folder Copying**: QC folder is always copied in TScan mode
- **Automatic Macro Subfolder Copying**: Macro subfolder is always copied automatically
- **Enhanced TScan Mode**: Better folder selection and validation
- **Improved Error Handling**: More robust error handling and recovery
- **PS2EXE Build System**: Professional executable building with PS2EXE

---

## 📝 Version History

### **Version 10.0 (Current)**
- ✅ **New Feature**: Automatic QC folder copying in TScan mode
- ✅ **New Feature**: Automatic macro subfolder copying in TScan mode
- ✅ **Improvement**: Enhanced TScan folder selection and validation
- ✅ **Improvement**: Better error handling and recovery
- ✅ **Technical**: Switched to PS2EXE build system for better reliability
- ✅ **Technical**: Improved Windows Forms compatibility

### **Previous Versions**
- **Version 9.x**: Initial release with basic copy modes
- **Version 8.x**: Enhanced progress tracking and error handling
- **Version 7.x**: Added TScan mode and folder selection

---

*CopyAmigo v10.0 - Making Survey Data Management Simple and Professional*

**Remember**: CopyAmigo is designed to be simple enough for anyone to use, while being powerful enough for professional survey work. If you're ever unsure about something, the program will guide you through it with clear messages and helpful suggestions.

**For Developers**: The executable is built using PS2EXE for maximum compatibility and reliability. See the "For Developers" section above for build instructions.
