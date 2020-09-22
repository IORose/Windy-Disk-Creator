# Windy Disk Creator

>![Windy Disk Creator Alpha](https://i.imgur.com/lJDhgtI.png)

This application is the Alpha version of Software, which is currently in active development.

    Requirements:
        * Mac OS X Yosemite 10.10 and up.
        * Windows 10 / 8.1 / 8 / 7 .iso Image.
        * Free Partition (size must be more, than .iso image size).
        * Created installer can be only booted from (U)EFI-based computer.
>
    How does this app work:
        1) Getting a list of mounted partitions in /Volumes/ directory, which is mountpoint for Internal/External partitions.
        2) Mounting Windows ISO image in /Volumes/ directory.
        3) Formatting selected patition into FAT32 File System with WINDY_****, where ***** - random sequence of english capital letters.
        4) Starting copying all installer files, except for sources/install.wim, which can be more than 4GB (It will be copied later).
        5) If the filesize of install.wim is less than 4GB, then it will be just directly copied to the sources/ directory, otherwise, if install.wim is more than 4GB, it will be splitted into parts via wimlib-imagex (wimlib is an open source, cross-platform library for creating, extracting, and modifying Windows Imaging (WIM) archives).
        6) If Windows 7 is choosen, bootmgfw.efi will be extracted from install.wim, then renamed (bootmgfw.efi -> bootx64.efi) and placed into /Volumes/partition/efi/boot/ directory.
        
