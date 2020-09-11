//
//  AppDelegate.swift
//  Windy Disk Creator
//
//  Created by WinterBoard on 28.08.2020.
//

import Cocoa



func getFileSize(path : String) -> UInt64{
    /*
     Функция для получения размера файла. В нашем случае проверка идет на install.wim,
     который может быть более 4GB (лимит FAT32)
     */
    do {
        return  (try FileManager.default.attributesOfItem(atPath: path) as NSDictionary).fileSize()
    } catch {
        print("Error: \(error)")
        return 0
    }
}



func randomString(length: Int) -> String {
    /*
     Функция для генерации случайных символов.
     Используется для задания имени форматированного раздела в FAT 32.
     Пример названия созданного раздела с генерацией символов этой функции: WINDY_POQAX
     */
    let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return String((0..<length).map{ _ in letters.randomElement()! })
}
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var isPreparingToKillShells = false
    let filePickerWindowsISO = NSOpenPanel()
    let wimlibPath = "\(String(Bundle.main.executablePath!).dropLast(24))Resources/.libs"
    var pidList = [Int32]()
    
    @IBOutlet weak var isoPathTextField: NSTextField!
 //   @IBOutlet weak var partitionPickerListPopUpButton: NSPopUpButtonCell!
    @IBOutlet weak var ISOPickerInput: NSTextField!
    @IBOutlet weak var StartButton: NSButton!
    @IBOutlet weak var UpdateButton: NSButton!
    @IBOutlet weak var ChooseButton: NSButton!
    @IBOutlet weak var ProgressBar: NSProgressIndicator!
    @IBOutlet weak var ShowOnlyExternalPartitionsCheckBox: NSButton!
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var CancelButton: NSButton!
    
    @IBOutlet weak var pickReborn: NSPopUpButton!
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        
    }
    
    @discardableResult
    func shell(_ command: String) -> String {
        /* Функция для вызова шелла.
         (Для выполнения терминальных команд) */
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
        /* Функция для изменения прогресса ProgressBar*/
        DispatchQueue.main.async {
            self.ProgressBar.doubleValue = progress
        }
    }
    
    func alertDialog(message: String){
        /*
         Функция для создания Alert-диалога, предупреждающего о неверной введенной
         информации.
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
         Функция создания и вызова диалога выбора файлов с указанными ниже параметрами.
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
                let result = filePickerWindowsISO.url // Pathname of the file
                
                if (result != nil) {
                    let path : String = result!.path
                    ISOPickerInput.stringValue = path
                }
                
            } else {
               // Пользователь нажал на "Отмена"
                return
            }
        }
    }
    
    func setGUIEnabledState(_ state : Bool)  {
        /*
         Изменение состояния активности у элементов интерфейса
         */
        DispatchQueue.main.async { [self] in
            
            ChooseButton.isEnabled = state
            UpdateButton.isEnabled = state
            StartButton.isEnabled = state
            pickReborn.isEnabled = state
            isoPathTextField.isEnabled = state
            ShowOnlyExternalPartitionsCheckBox.isEnabled = state
            window!.standardWindowButton(.closeButton)!.isEnabled = state
            
        }
    }
    
    
    @IBAction func OnClickExternalPartitionsPickerUpdateButton(_ sender: Any) {
        /*
         Функция, выполняющаяся по нажатию на кнопку "Update" в выборе разделов.
         Неоюходима для поиска внешних смонтированных разделов на компьютере Mac.
         */
        pickReborn.removeAllItems()
             do {
            /*
             Получение списка смонтированных разделов в каталоге /Volumes
             */
            let unfilteredPartitionsArray = try FileManager.default.contentsOfDirectory(atPath: "/Volumes/")
            print("[DEBUG] > Partitions: \(unfilteredPartitionsArray)")
            /*
             Фильтрация внешних разделов от внутренних с помощью diskutil,
             т.к. Swift не позволяет это сделать своими средствами
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
                    pickReborn.addItem(withTitle: unfilteredSinglePartition)
                    print("[DEBUG] > Adding (\(unfilteredSinglePartition)) partition to picker.")
                }
                
                
            }
            
        } catch {
            print("[ERROR] > Something went wrong: \(error)")
        }

        if (!pickReborn.itemArray.isEmpty) {
           pickReborn.isEnabled = true
        }
        else{
           pickReborn.isEnabled = false
            pickReborn.addItem(withTitle: "No Partitions were detected")
        }
        
    }
    
    
    
    @IBAction func OnClickStartButton(_ sender: Any) {
        /*
         Функция, проверяющая правильность введенной информации
         */
        var counter: Int8 = 0
        print(isoPathTextField.stringValue)
        if !(isoPathTextField.stringValue.hasSuffix(".iso")) {
            counter = 2
        }
        
        if (pickReborn.title == "No Partitions were detected" || pickReborn.stringValue.isEmpty) {
            counter+=1
        }
        /*
         Проверка "чего нехватает"
         */
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
                 Проверка данных успешна. Приступаем к созданию загрузочного раздела.
                 */
                setGUIEnabledState(false)
                setProgress(5)
                startDiskCreating(windowsISO: isoPathTextField.stringValue, partition: pickReborn.title)
            } else {
                alertDialog(message: "Selected \"\(isoPathTextField.stringValue)\" does not exist.")
            }
            
        }
    }
    
    func stopBackgroundTransfering() {
        /*
         Функция для остановки создания загрузочной флешки.
         Работает путём "убивания" процессов, созданных через функцию shell()
         */
        
        for pid in pidList{
            
            shell("kill -9 \(pid)")
        }
        pidList.removeAll()
        isPreparingToKillShells = true
    }
    
    func formatPartition(_ volumeUDID : String, newPartitionName: String){
        /*
         Функция для форматирования выбранного раздела по его UUID (в целях безопасности)
         в файловую систему FAT32 с названием WINDY_***** (вместо ***** генерируются случайные буквы)
         */
        print("[DEBUG] > New Partition Name: \(newPartitionName)")
        print(shell("diskutil eraseVolume FAT32 \(newPartitionName) \(volumeUDID)"))
    }
    func startDiskCreating(windowsISO : String, partition : String) {
        /*
         Функция, с которой начинается создание загрузочного раздела.
         */
        DispatchQueue.global(qos: .background).async {  [self] in
            
            setProgress(1)
            
            let volumeUDID = String(shell("diskutil info \"/Volumes/\(partition)\" | grep 'Volume UUID:'").dropFirst(30))
            
            setProgress(3)
            
            /*
             Монтирование образа Windows.iso в /Volumes/
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
                
                setProgress(0)
                
                alertDialog(message: "An Error was occured when trying to mount .iso image. It can be related to corrupted image or to macOS Bug.")
                setGUIEnabledState(true)
                cancelButtonHiddenState(true)
                return
                
            }
            
            
            hdiutilMountPath = String(hdiutilMountPath.dropLast())
            
            setProgress(8)
            
            let randomPartitionName = ("WINDY_\(randomString(length: 5))")
            /*
             Форматирование раздела с выбранными параметрами.
             */
            formatPartition(volumeUDID, newPartitionName: randomPartitionName)
            setProgress(14)
            print("[DEBUG] > Mounting Windows in Finder")
            
            
            /*
             Копирование ресурсов установщика на раздел FAT32
             */
            print("[DEBUG] > Starting resources copying to Destination partition /Volumes/\(randomPartitionName)")
            if (!isPreparingToKillShells){
                setProgress(50)
                /*
                 Копирование ресурсов установщика без install.wim, т.к. его размер может быть более 4GB
                 */
                print(shell("rsync -av --exclude='sources/install.wim' \"\(hdiutilMountPath)/\" /Volumes/\(randomPartitionName)"))
                
                setProgress(70)
            }
            else{
                setGUIEnabledState(true)
                cancelButtonHiddenState(true)
                return
            }
            /*
             Проверка Install.wim на размер и его копирование (если размер более 4GB, то будет произведено разделение
             install.wim на части)
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
        }
        
    }
    
}


