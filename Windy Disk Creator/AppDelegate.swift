//
//  AppDelegate.swift
//  Windy Disk Creator
//
//  Created by WinterBoard on 28.08.2020.
//

import Cocoa

extension String {
    var localized: String {
        return NSLocalizedString(self, comment:"")
    }
}

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
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var updateButton: NSButton!
    @IBOutlet weak var chooseButton: NSButton!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var showOnlyExternalPartitionsCheckBox: NSButton!
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var cancelButton: NSButton!
    @IBOutlet weak var pickerPopUpButton: NSPopUpButton!
    @IBOutlet weak var visualEffect: NSVisualEffectView!
    @IBOutlet weak var osVersionPickerPopUpButton: NSPopUpButton!
    @IBOutlet weak var osVersionPickerTextLabel: NSTextField!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window?.isMovableByWindowBackground = true
        window?.contentView = visualEffect
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        print("[DEBUG] Interrupting processes and exiting...")
        stopBackgroundTransfering()
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
    
    
    func setCancelButtonHiddenState(_ state : Bool) {
        DispatchQueue.main.async { [self] in
            cancelButton.isHidden = state
        }
    }
    
    func setProgress(_ progress : Double){
        /*
         Changing the ProgressBar progress
         */
        DispatchQueue.main.async {
            self.progressBar.doubleValue = progress
        }
    }
    
    func alertDialog(message: String){
        /*
         Alert Dialog, which warn user about incorrect input data.
         */
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.addButton(withTitle: "Close".localized)
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
            
            chooseButton.isEnabled = state
            updateButton.isEnabled = state
            startButton.isEnabled = state
            pickerPopUpButton.isEnabled = state
            isoPathTextField.isEnabled = state
            showOnlyExternalPartitionsCheckBox.isEnabled = state
            window!.standardWindowButton(.closeButton)!.isEnabled = state
            osVersionPickerPopUpButton.isEnabled = state
            osVersionPickerTextLabel.isEnabled = state
            
            state ? (osVersionPickerTextLabel.textColor = .black) : (osVersionPickerTextLabel.textColor = .lightGray)
            
        }
    }
    
    func onInterruptDiskCreating() {
        setGUIEnabledState(true)
        setCancelButtonHiddenState(true)
        setProgress(0)
        DispatchQueue.main.async {
            self.pickerPopUpButton.removeAllItems()
        }
    }
    @IBAction func OnClickExternalPartitionsPickerUpdateButton(_ sender: Any) {
        /*
         OnClick event on "Update" button.
         It's using for updating mounted Internal/External partitions.
         */
        pickerPopUpButton.removeAllItems()
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
            if (showOnlyExternalPartitionsCheckBox.state == .on){
                rawDiskUtilOutput = shell("diskutil list -plist external physical")
            }
            else{
                rawDiskUtilOutput = shell("diskutil list -plist physical")
            }
            
            print(unfilteredPartitionsArray)
            for unfilteredSinglePartition in unfilteredPartitionsArray{
                if(rawDiskUtilOutput).contains("<string>/Volumes/\(unfilteredSinglePartition)</string>"){
                    pickerPopUpButton.addItem(withTitle: unfilteredSinglePartition)
                    print("[DEBUG] > Adding (\(unfilteredSinglePartition)) partition to picker.")
                }
                
                
            }
            
        } catch {
            print("[ERROR] > Something went wrong: \(error)")
        }
        
        if (!pickerPopUpButton.itemArray.isEmpty) {
            pickerPopUpButton.isEnabled = true
        }
        else{
            pickerPopUpButton.isEnabled = false
            pickerPopUpButton.addItem(withTitle: "No Partitions were detected".localized)
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
        
        if (pickerPopUpButton.title == "No Partitions were detected".localized || pickerPopUpButton.title.isEmpty) {
            counter+=1
        }
        
        switch counter {
        case 2:
            alertDialog(message: "Windows ISO was not selected.".localized)
            break
        case 1:
            alertDialog(message: "No partition was selected.".localized)
            break
        case 3:
            alertDialog(message: "No options were selected. Please select a Windows.iso and an External Partition.".localized)
            break
        default:
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: isoPathTextField.stringValue) {
                /*
                 Input check done. All information is correct (probably)
                 */
                setGUIEnabledState(false)
                setProgress(5)
                startDiskCreating(windowsISO: isoPathTextField.stringValue, partition: pickerPopUpButton.title)
            } else {
                alertDialog(message: "\("Windows ISO at path: ".localized)\"\(isoPathTextField.stringValue)\"\(" does not exist. Check the entered path and try again.".localized)")
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
                setCancelButtonHiddenState(false)
                
                if (checkIfDirectoryExists("\(hdiutilMountPath)/efi/boot")) {
                    
                }
                DispatchQueue.main.async {
                checkIfDirectoryExists("\(hdiutilMountPath.dropLast())/efi/boot") ? (osVersionPickerPopUpButton.selectItem(at: 1)) : (osVersionPickerPopUpButton.selectItem(at: 2))
                }
            }
            else{
                print("[ERROR] > Can't mount .iso image. It may be corrupted or its just a macOS bug (detected in Big Sur Beta 6).")
                alertDialog(message: "\("An Error was occured when trying to mount .iso image. It can be related to corrupted image or to macOS Bug. If you sure that your ISO image is correct, then try to mount it via Terminal:\n\n".localized)\("sudo hdiutil attach \"\(windowsISO)\" ")\("\n\nAnd then try again.".localized)")

                onInterruptDiskCreating()
                return
                
            }
            
            hdiutilMountPath = String(hdiutilMountPath.dropLast())
            
            let windowsPartitionSize = Int64(getStringBetween(shell("diskutil info \"\(hdiutilMountPath)\" | grep \'Volume Total Space:\'"), firstPart: " (", secondPart: " Bytes)"))!
            if(!checkIfDirectoryExists("/Volumes/\(partition)")){
                print("[DEBUG] > Partition was disconnected. Aborting...")
                alertDialog(message: "Selected partition was disconnected. Aborting the operation.".localized)
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
            print(hdiutilMountPath)
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
                    print("[DEBUG] >  File size is less than 4000MB (\(installWimSize)MB). Don't need to split install.wim.")
                    print("[DEBUG] > Copying unmodified install.wim")
                    print(shell("rsync -av \"\(hdiutilMountPath)/sources/install.wim\" /Volumes/\(randomPartitionName)/sources/"))
                }
                
            }
            /*
             Checking Windows Version ( 10 / 8.1 / 8 / 7 ). If Windows 7 has been choosen,
             then bootmgfw.efi will be extracted from install.wim, then renamed (bootmgfw.efi -> bootx64.efi) and placed into /Volumes/partition/efi/boot/ directory.
             */
            if (!isPreparingToKillShells){
                DispatchQueue.main.async {
                    if (osVersionPickerPopUpButton.indexOfSelectedItem == 2){
                        setProgress(90)
                        print("[DEBUG] > ISO Type: Windows 7. Installing EFI Bootloader...")
                        let command =  "\"\(wimlibPath)/wimlib-imagex\" extract \"\(hdiutilMountPath)/sources/install.wim\" 1 /Windows/Boot/EFI/bootmgfw.efi --dest-dir=\"/Volumes/\(randomPartitionName)/efi/boot/\""
                        print(shell(command))
                        print(shell("mv /Volumes/\(randomPartitionName)/efi/boot/bootmgfw.efi /Volumes/\(randomPartitionName)/efi/boot/bootx64.efi"))
                        print("[DEBUG] Bootloader has been installed.")
                    }
                    else {
                        print("[DEBUG] > ISO Type: Windows 8 or newer. Bootloader is already installed.")
                    }
                }
            }
            setProgress(100)
            setGUIEnabledState(true)
            setCancelButtonHiddenState(true)
            DispatchQueue.main.async {
                pickerPopUpButton.removeAllItems()
            }
            alertDialog(message: "Done.".localized)
            
        }
        
    }
    
}


