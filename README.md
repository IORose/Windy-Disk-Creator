# Windy Disk Creator

>![Windy Disk Creator Alpha](https://i.ibb.co/j4dL8gp/Winterboard-Preview-Screenshot.png)

This application is the Alpha version of Software, which is currently in active development.

    Requirements:
        * macOS Catalina 10.15 and up (But you can probably rebuild project with lower target version).
        * Windows 10 .iso Image.
        * Free Partition (size must be more, than .iso image size).
        * Created installer can be only booted from (U)EFI-based computer.
>
    How does this app work:
        1) Getting a list of mounted partitions in /Volumes/ directory, which is mountpoint for Internal/External partitions.
        2) Mounting Windows 10 ISO image in /Volumes/ directory.
        3) Formatting selected patition into FAT32 File System with WINDY_****, where ***** - random sequence of english capital letters.
        4) Starting copying all installer files, except for sources/install.wim, which can be more than 4GB (It will be copied later).
        5) If the filesize of install.wim is less than 4GB, then it will be just directly copied to the sources/ directory, otherwise, if install.wim is more than 4GB, it will be splitted into parts via wimlib-imagex (wimlib is an open source, cross-platform library for creating, extracting, and modifying Windows Imaging (WIM) archives).
        
