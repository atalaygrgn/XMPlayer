local categories = {
    { 
        id = "settings", 
        name = "Settings", 
        icon = "assets/icons/settings.png",
        path = nil, -- Settings might have its own logic
        filter = nil
    },
    { 
        id = "photo", 
        name = "Photos", 
        icon = "assets/icons/photo.png", 
        path = "/mnt/sdcard/MUSIC",
        filter = "photo"
    },
    { 
        id = "music", 
        name = "Music", 
        icon = "assets/icons/music.png", 
        path = "/mnt/sdcard/MUSIC",
        filter = "music"
    },
    { 
        id = "video", 
        name = "Videos", 
        icon = "assets/icons/video.png", 
        path = "/mnt/sdcard/ROMS/Video",
        filter = "video"
    },
    { 
        id = "folder", 
        name = "Folders", 
        icon = "assets/icons/folder.png", 
        path = "/mnt/sdcard",
        filter = nil -- Show all
    },
}

return categories
