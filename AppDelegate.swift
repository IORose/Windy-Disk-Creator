//
//  AppDelegate.swift
//  Windy Disk Creator
//
//  Created by WinterBoard on 28.08.2020.
//

import Cocoa

func shell(_ command: String) -> String {
    //Функция для вызова шелла. (Для выполнения терминальных команд)
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/bash"
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    
    return output
}
func getFileSize(path : String) -> UInt64{
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
    
    let dialog = NSOpenPanel()
    @IBOutlet var window: NSWindow!
    @IBOutlet weak var ISOPickerInput: NSTextField!
    var externalPartitions = [String]()
    
    func alert(message: String){
        /*
         Функция для создания Alert-диалога, предупреждающего о неверной введенной
         информации.
         */
        let alert = NSAlert()
        alert.addButton(withTitle: "Close")
        alert.messageText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
    @IBAction func ISOPickerButton(_ sender: Any) {
        /*
         Функция создания и вызова диалога выбора файлов с указанными ниже параметрами.
         */
        dialog.title                   = "Choose a Windows 10 ISO"
        dialog.showsResizeIndicator    = false
        dialog.showsHiddenFiles        = false
        dialog.allowsMultipleSelection = false
        dialog.canChooseDirectories    = false
        dialog.canChooseFiles          = true
        dialog.allowedFileTypes        = ["iso"]
        
        if (dialog.runModal() ==  NSApplication.ModalResponse.OK) {
            let result = dialog.url // Pathname of the file
            
            if (result != nil) {
                let path : String = result!.path
                ISOPickerInput.stringValue = path
            }
            
        } else {
            // User clicked on "Cancel"
            return
        }
    }
    
    @IBOutlet weak var isoPath: NSTextField!
    @IBOutlet weak var partitionPickerListVar: NSPopUpButtonCell!
    @IBAction func partitionPickerList(_ sender: Any) {
        /*
         Функция, применяющая заголовок пикеру разделов.
         Использование обязательно, т.к. в Swift без неё не будет заголовка
         выбранного элемента.
         */
        partitionPickerListVar.setTitle(partitionPickerListVar.titleOfSelectedItem)
        
    }
    
    @IBAction func ExternalPartitionsPickerUpdate(_ sender: Any) {
        /*
         Функция, выполняющаяся по нажатию на кнопку "Update" в выборе разделов.
         Неоюходима для поиска внешних смонтированных разделов на компьютере Mac.
         */
        externalPartitions.removeAll()
        do {
            /*
             Получение списка смонтированных разделов в каталоге /Volumes
             */
            let unfilteredPartitions = try FileManager.default.contentsOfDirectory(atPath: "/Volumes/")
            print("[DEBUG] > Partitions: \(unfilteredPartitions)")
            /*
             Фильтрация внешних разделов от внутренних с помощью diskutil,
             т.к. Swift не позволяет это сделать своими средствами
             */
            let rawDiskUtil = shell("diskutil list -plist external physical")
            for unfilteredSinglePartition in unfilteredPartitions{
                if(rawDiskUtil).contains("<string>/Volumes/\(unfilteredSinglePartition)</string>"){
                    externalPartitions.append(unfilteredSinglePartition)
                }
                
                
            }
            print("[DEBUG] > External Partitions: \(externalPartitions)")
            
        } catch {
            print(error)
        }
        if (!externalPartitions.isEmpty) {
            partitionPickerListVar.isEnabled = true
            partitionPickerListVar.addItems(withTitles: externalPartitions)
            partitionPickerListVar.setTitle("Choose the Partition")
        }
        else{
            partitionPickerListVar.isEnabled = false
            partitionPickerListVar.setTitle("No External Partitions were detected")
        }
        
    }
    
    @IBAction func checkInputInfo(_ sender: Any) {
        /*
         Функция, проверяющая правильность введенной информации
         */
        var counter: Int8 = 0
        print(isoPath.stringValue)
        if !(isoPath.stringValue.hasSuffix(".iso")) {
            counter = 2
        }
        
        if (partitionPickerListVar.title == "Choose the Partition" || partitionPickerListVar.title == "Click the \"Update\" button first" || partitionPickerListVar.title == "No External Partitions were detected") {
            counter+=1
        }
        /*
         Проверка "чего нехватает"
         */
        switch counter {
        case 2:
            alert(message: "Windows ISO was not selected.")
            break
        case 1:
            alert(message: "No partition was selected.")
            break
        case 3:
            alert(message: "No options were selected. Please select a Windows.iso and an External Partition.")
            break
        default:
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: isoPath.stringValue) {
                /*
                 Проверка данных успешна. Приступаем к созданию загрузочного раздела.
                 */
                startDiskCreating(windowsISO: isoPath.stringValue, partition: partitionPickerListVar.title)
            } else {
                alert(message: "Selected \"\(isoPath.stringValue)\" does not exist.")
            }
            
        }
    }
    
    @IBAction func DebugButtonAction(_ sender: Any) {
        /*
         Функция, не несущая смысла для пользователя. Отладочная информация и "полигон испытаний"
         */
        
        
        // print(shell("/Users/winterboard/Desktop/wimlib/wimlib-imagex"))
        
        let appFolder = Bundle.main.executablePath
                print(appFolder)
    
    }
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        
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
        let volumeUDID = String(shell("diskutil info \"/Volumes/\(partition)\" | grep 'Volume UUID:'").dropFirst(30))
        
        
        let randomPartitionName = ("WINDY_\(randomString(length: 5))")
        /*
         Форматирование раздела с выбранными параметрами. (ВРЕМЕННО ОТКЛЮЧЕНО ДЛЯ УМЕНЬШЕНИЯ ИЗНОСА НАКОПИТЕЛЯ)
         
         //
         */
        
        
        formatPartition(volumeUDID, newPartitionName: randomPartitionName)
        
        print("[DEBUG] > Mounting Windows in Finder")
        var hdiutilMountPath = shell("hdiutil attach \"\(windowsISO)\"  -mountroot /Volumes/ -readonly")
        
        if let range = hdiutilMountPath.range(of: "/Volumes/") {
            hdiutilMountPath = String(hdiutilMountPath.dropFirst(hdiutilMountPath.distance(from: hdiutilMountPath.startIndex, to: range.lowerBound)))
        }
        
        hdiutilMountPath = String(hdiutilMountPath.dropLast())
        
        print(hdiutilMountPath)
        
        print("[DEBUG] > Starting resources copying to Destination partition /Volumes/\(randomPartitionName)")
        
        print(shell("rsync -av --exclude='sources/install.wim' \"\(hdiutilMountPath)/\" /Volumes/\(randomPartitionName)"))
        
        
        let fileSize = getFileSize(path: "\(hdiutilMountPath)/sources/install.wim") / 1024 / 1024
        if(fileSize > 4000){
            print("[DEBUG] > File is too large (\(fileSize)MB) and needs to be splitted into parts.")
            print("[DUBUG] > Starting splitting (and copying)")
            print(shell("/Users/winterboard/Desktop/wimlib/wimlib-imagex split \"\(hdiutilMountPath)/sources/install.wim\" /Volumes/\(randomPartitionName)/sources/install.swm  \(fileSize/2) --include-integrity"))
        }
        else {
            print("[DEBUG] >  File size is less than 4000MB (\(fileSize)). Don't need to split install.wim.")
            print("[DEBUG] > Copying unmodified install.wim")
            print(shell("rsync -av \"\(hdiutilMountPath)/sources/install.wim\" /Volumes/\(randomPartitionName)/sources/"))
        }
        
    }
    
}


