//
//  AppDelegate.swift
//  Windy Disk Creator
//
//  Created by WinterBoard on 28.08.2020.
//

import Cocoa



func getFileSize(path : String) -> UInt64{
    /*
     Getting file size. In our case, we are checking for install.wim size,
     which can be more than 4GB (FAT32 Limit).
     */
    do {
        return  (try FileManager.default.attributesOfItem(atPath: path) as NSDictionary).fileSize()
    } catch {
        print("Error: \(error)")
        return 0
    }
}
func checkIfDirectoryExists(_ fullPath : String) -> Bool{
    let fileManager = FileManager.default
    var isDir : ObjCBool = false
    if fileManager.fileExists(atPath: fullPath, isDirectory:&isDir) {
        if isDir.boolValue {
            // file exists and is a directory
            return true
        }
    }
    return false
}

func randomString(length: Int) -> String {
    /*
     Generating random symbols.
     It's using to set random name on formated FAT32 Partition.
     Example: WINDY_P0QAX, where P0QAX - random sequence of 5 symbols.
     */
    let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return String((0..<length).map{ _ in letters.randomElement()! })
}

func getStringBetween(_ originalString : String, firstPart : String, secondPart : String) -> String{
    if let range = originalString.range(of: firstPart) {
        var stringOutput = String(originalString.dropFirst(originalString.distance(from: originalString.startIndex, to: range.upperBound)))
        if let range = stringOutput.range(of: secondPart) {
            stringOutput = String(stringOutput[..<range.lowerBound])
            return stringOutput
        }
    }
    return ""
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var isPreparingToKillShells = false
    let filePickerWindowsISO = NSOpenPanel()
    let wimlibPath = "\(String(Bundle.main.executablePath!).dropLast(24))Resources/.libs"
    var pidList = [Int32]()
    
   
    @IBOutlet weak var isoPathTextField: NSTextField!
    // @IBOutlet weak var ISOPickerInput: NSTextField!
    @IBOutlet weak var StartButton: NSButton!
    @IBOutlet weak var UpdateButton: NSButton!
    @IBOutlet weak var ChooseButton: NSButton!
    @IBOutlet weak var ProgressBar: NSProgressIndicator!
    @IBOutlet weak var ShowOnlyExternalPartitionsCheckBox: NSButton!
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var CancelButton: NSButton!
    @IBOutlet weak var PickerPopUpButton: NSPopUpButton!
    @IBOutlet weak var visualEffect: NSVisualEffectView!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window?.isMovableByWindowBackground = true
        window?.contentView = visualEffect
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        print("[DEBUG] Exiting...")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApplication.shared.terminate(self)
        return true
    }
    
    @discardableResult
    func shell(_ command: String) -> String {
        /* Executing Shell commands.
         It's using to call diskutil and rsync commands.*/
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.launch()
        pidList.append(task.processIdentifier)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        return output
        
    }
    
    func cancelButtonHiddenState(_ state : Bool) {
        DispatchQueue.main.async { [self] in
            CancelButton.isHidden = state
        }
    }
    
    func setProgress(_ progress : Double){
        /*
         Changing the ProgressBar progress
         */
        DispatchQueue.main.async {
            self.ProgressBar.doubleValue = progress
        }
    }
    
    func alertDialog(message: String){
        /*
         Alert Dialog, which warn user about incorrect input data.
         */
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.addButton(withTitle: "Close")
            alert.messageText = message
            alert.alertStyle = .critical
            alert.runModal()
        }
    }
    
    @IBAction func OnClickCancelButton(_ sender: Any) {
        stopBackgroundTransfering()
    }
    
    @IBAction func ISOPickerButton(_ sender: Any) {
        /*
         Calling System Documents picker to pick an .iso file.
         */
        DispatchQueue.main.async { [self] in
            
            filePickerWindowsISO.title                   = "Choose a Windows 10 ISO"
            filePickerWindowsISO.showsResizeIndicator    = false
            filePickerWindowsISO.showsHiddenFiles        = false
            filePickerWindowsISO.allowsMultipleSelection = false
            filePickerWindowsISO.canChooseDirectories    = false
            filePickerWindowsISO.canChooseFiles          = true
            filePickerWindowsISO.allowedFileTypes        = ["iso"]
            
            if (filePickerWindowsISO.runModal() ==  NSApplication.ModalResponse.OK) {
                let result = filePickerWindowsISO.url
                
                if (result != nil) {
                    let path : String = result!.path
                    isoPathTextField.stringValue = path
                }
                
            } else {
                // User clicked on "Close" button.
                return
            }
        }
    }
    
    func setGUIEnabledState(_ state : Bool)  {
        /*
         Changing GUI Active state
         */
        DispatchQueue.main.async { [self] in
            
            ChooseButton.isEnabled = state
            UpdateButton.isEnabled = state
            StartButton.isEnabled = state
            PickerPopUpButton.isEnabled = state
            isoPathTextField.isEnabled = state
            ShowOnlyExternalPartitionsCheckBox.isEnabled = state
            window!.standardWindowButton(.closeButton)!.isEnabled = state
            
        }
    }
    
    func onInterruptDiskCreating() {
        setGUIEnabledState(true)
        cancelButtonHiddenState(true)
        setProgress(0)
        DispatchQueue.main.async {
            self.PickerPopUpButton.removeAllItems()
        }
    }
    @IBAction func OnClickExternalPartitionsPickerUpdateButton(_ sender: Any) {
        /*
         OnClick event on "Update" button.
         It's using for updating mounted Internal/External partitions.
         */
        PickerPopUpButton.removeAllItems()
        do {
            /*
             Getting mounted partitions in /Volumes/
             */
            let unfilteredPartitionsArray = try FileManager.default.contentsOfDirectory(atPath: "/Volumes/")
            print("[DEBUG] > Partitions: \(unfilteredPartitionsArray)")
            /*
             Partition filtering [Internal/External] using diskutil,
             because this feature is not natively available in Swift.
             */
            
            var rawDiskUtilOutput : String
            if (ShowOnlyExternalPartitionsCheckBox.state == .on){
                rawDiskUtilOutput = shell("diskutil list -plist external physical")
            }
            else{
                rawDiskUtilOutput = shell("diskutil list -plist physical")
            }
            
            print(unfilteredPartitionsArray)
            for unfilteredSinglePartition in unfilteredPartitionsArray{
                if(rawDiskUtilOutput).contains("<string>/Volumes/\(unfilteredSinglePartition)</string>"){
                    PickerPopUpButton.addItem(withTitle: unfilteredSinglePartition)
                    print("[DEBUG] > Adding (\(unfilteredSinglePartition)) partition to picker.")
                }
                
                
            }
            
        } catch {
            print("[ERROR] > Something went wrong: \(error)")
        }
        
        if (!PickerPopUpButton.itemArray.isEmpty) {
            PickerPopUpButton.isEnabled = true
        }
        else{
            PickerPopUpButton.isEnabled = false
            PickerPopUpButton.addItem(withTitle: "No Partitions were detected")
        }
        
    }
    
    
    
    @IBAction func OnClickStartButton(_ sender: Any) {
        /*
         Checking correctness of input data.
         */
        var counter: Int8 = 0
        print(isoPathTextField.stringValue)
        if !(isoPathTextField.stringValue.hasSuffix(".iso")) {
            counter = 2
        }
        
        if (PickerPopUpButton.title == "No Partitions were detected" || PickerPopUpButton.title.isEmpty) {
            counter+=1
        }
        
        switch counter {
        case 2:
            alertDialog(message: "Windows ISO was not selected.")
            break
        case 1:
            alertDialog(message: "No partition was selected.")
            break
        case 3:
            alertDialog(message: "No options were selected. Please select a Windows.iso and an External Partition.")
            break
        default:
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: isoPathTextField.stringValue) {
                /*
                 Input check done. All information is correct (probably)
                 */
                setGUIEnabledState(false)
                setProgress(5)
                startDiskCreating(windowsISO: isoPathTextField.stringValue, partition: PickerPopUpButton.title)
            } else {
                alertDialog(message: "Selected \"\(isoPathTextField.stringValue)\" does not exist.")
            }
            
        }
    }
    
    func stopBackgroundTransfering() {
        /*
         Force stop of copying files via killing processes,
         which were executed with shell().
         */
        
        for pid in pidList{
            shell("kill -9 \(pid)")
        }
        pidList.removeAll()
        isPreparingToKillShells = true
    }
    
    func formatPartition(_ volumeUDID : String, newPartitionName: String){
        /*
         Formatting selected partition by its UUID (in terms of safety)
         in FAT32 FileSystem with WINDY_***** name (where ***** - random letters).
         */
        print("[DEBUG] > New Partition Name: \(newPartitionName)")
        print(shell("diskutil eraseVolume FAT32 \(newPartitionName) \(volumeUDID)"))
    }
    func startDiskCreating(windowsISO : String, partition : String) {
        /*
         Starting disk creating process.
         */
        isPreparingToKillShells = false
        DispatchQueue.global(qos: .background).async {  [self] in
            
            setProgress(1)
            
            let volumeUDID = String(shell("diskutil info \"/Volumes/\(partition)\" | grep 'Volume UUID:'").dropFirst(30))
            
            setProgress(3)
            
            /*
             Attempting to mount Windows.iso in /Volumes/
             */
            
            var hdiutilMountPath = shell("hdiutil attach \"\(windowsISO)\"  -mountroot /Volumes/ -readonly")
            if (!hdiutilMountPath.isEmpty) {
                print("[DEBUG] > Image was mounted successfully.")
                
                setProgress(6)
                
                if let range = hdiutilMountPath.range(of: "/Volumes/") {
                    hdiutilMountPath = String(hdiutilMountPath.dropFirst(hdiutilMountPath.distance(from: hdiutilMountPath.startIndex, to: range.lowerBound)))
                }
                cancelButtonHiddenState(false)
                
            }
            else{
                print("[ERROR] > Can't mount .iso image. It may be corrupted or its just a macOS bug (detected in Big Sur Beta 6).")
                alertDialog(message: "An Error was occured when trying to mount .iso image. It can be related to corrupted image or to macOS Bug.")
                onInterruptDiskCreating()
                return
                
            }
            
            hdiutilMountPath = String(hdiutilMountPath.dropLast())
            
            let windowsPartitionSize = Int64(getStringBetween(shell("diskutil info \"\(hdiutilMountPath)\" | grep \'Volume Total Space:\'"), firstPart: " (", secondPart: " Bytes)"))!
            if(!checkIfDirectoryExists("/Volumes/\(partition)")){
                print("[DEBUG] > Partition was disconnected. Aborting...")
                alertDialog(message: "Selected partition was disconnected. Aborting the operation.")
                onInterruptDiskCreating()
                return
            }
            let choosenPartitionSize = Int64(getStringBetween(shell("diskutil info \"\(partition)\" | grep \'Volume Total Space:\'"), firstPart: " (", secondPart: " Bytes)"))!
            print("[DEBUG] > Windows: (\(windowsPartitionSize) Bytes)")
            print("[DEBUG] > Choosen Partition Size: (\(choosenPartitionSize) Bytes)")
            if windowsPartitionSize > (choosenPartitionSize + 100000000) {
                print("[DEBUG] > Oversized .iso Image. Aborting writing.")
                alertDialog(message: "This .iso Image (\(windowsPartitionSize / 1024 / 1024)MB) can't fit into choosen partition (\(choosenPartitionSize / 1024 / 1024)MB)")
                onInterruptDiskCreating()
                return
            }
            
            setProgress(8)
            
            let randomPartitionName = ("WINDY_\(randomString(length: 5))")
            
            formatPartition(volumeUDID, newPartitionName: randomPartitionName)
            setProgress(14)
            
            
            /*
             Copying Windows installer into WINDY_***** partition.
             */
            print("[DEBUG] > Starting resources copying to Destination partition /Volumes/\(randomPartitionName)")
            if (!isPreparingToKillShells){
                setProgress(50)
                /*
                 Copying installer resources, except for install.wim, because its size can be more than 4GB, which is FAT32 limit.
                 */
                print(shell("rsync -av --exclude='sources/install.wim' \"\(hdiutilMountPath)/\" /Volumes/\(randomPartitionName)"))
                
                setProgress(70)
            }
            else{
                onInterruptDiskCreating()
                return
            }
            /*
             Getting Install.wim size and copying it to the destination. (If Install.wim size is more than 4GB,
             then this image will be devided into parts.
             */
            if (!isPreparingToKillShells){
                let installWimSize = getFileSize(path: "\(hdiutilMountPath)/sources/install.wim") / 1024 / 1024
                if(installWimSize > 4000){
                    print("[DEBUG] > File is too large (\(installWimSize)MB) and needs to be splitted into parts.")
                    print("[DUBUG] > Starting splitting (and copying)")
                    print(shell("\"\(wimlibPath)/wimlib-imagex\" split \"\(hdiutilMountPath)/sources/install.wim\" \"/Volumes/\(randomPartitionName)/sources/install.swm\"  \(installWimSize/2) --include-integrity"))
                }
                else {
                    print("[DEBUG] >  File size is less than 4000MB (\(installWimSize)). Don't need to split install.wim.")
                    print("[DEBUG] > Copying unmodified install.wim")
                    print(shell("rsync -av \"\(hdiutilMountPath)/sources/install.wim\" /Volumes/\(randomPartitionName)/sources/"))
                }
                
            }
            setProgress(100)
            setGUIEnabledState(true)
            cancelButtonHiddenState(true)
            DispatchQueue.main.async {
                PickerPopUpButton.removeAllItems()
            }
        }
        
    }
    
}


