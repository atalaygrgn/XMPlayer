local menu_data = {
    root = {
        categories = {
            {
                id = "settings",
                name = "Settings",
                icon = "assets/icons/settings.png",
                path = nil,
                filter = nil,
            },
            {
                id = "photo",
                name = "Photo",
                icon = "assets/icons/photo.png",
                path = nil,
                filter = "photo",
            },
            {
                id = "music",
                name = "Music",
                icon = "assets/icons/music.png",
                path = nil,
                filter = "music",
            },
            {
                id = "video",
                name = "Video",
                icon = "assets/icons/video.png",
                path = nil,
                filter = "video",
            },
            {
                id = "folder",
                name = "Files",
                icon = "assets/icons/folders.png",
                path = "/",
                filter = nil,
            },
        }
    }
}

function menu_data.get_root_categories()
    return menu_data.root.categories
end

return menu_data
