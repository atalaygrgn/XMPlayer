local categories = {
    { 
        id = "settings", 
        name = "Settings", 
        icon = "assets/icons/settings.png",
        path = nil,
        filter = nil
    },
    { 
        id = "photo", 
        name = "Photo", 
        icon = "assets/icons/photo.png", 
        path = "/mnt/sdcard/PICTURES",
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
        name = "Video", 
        icon = "assets/icons/video.png", 
        path = "/mnt/sdcard/ROMS/Video",
        filter = "video"
    },
    { 
        id = "folder", 
        name = "Files", 
        icon = "assets/icons/drive.png", 
        path = "/mnt/sdcard",
        filter = nil -- Show all
    },
}

return categories
