local xmb_state = {}

function xmb_state.new()
    local state = {
        current_category_idx = 3,
        current_item_idx = 1,

        playlist_sidebar_active = false,
        playlist_sidebar_alpha = 0,
        playlist_sidebar_items = {},
        playlist_sidebar_selected_idx = 1,
        playlist_sidebar_scroll_y = 0,
        playlist_sidebar_target_scroll_y = 0,
        playlist_sidebar_track_to_add = nil,

        category_scroll_x = 0,
        target_category_scroll_x = 0,
        item_scroll_y = 0,
        target_item_scroll_y = 0,

        list_slide_x = 0,
        list_slide_alpha = 1,

        nav_stack = {},
        view_type = "browser",
        view_data = nil,

        repeat_timer = 0,
        last_key = nil,
        scroll_held_count = 0,

        thumbs = {},
        orientations = {},
        thumb_status = {},

        context_menu = {
            active = false,
            alpha = 0,
            selected_idx = 1,
            title = "",
            items = {},
            target_path = nil,
        },
    }

    function state.reset_navigation()
        state.current_item_idx = 1
        state.nav_stack = {}
        state.view_type = "browser"
        state.view_data = nil
    end

    function state.reset_animations()
        state.category_scroll_x = 0
        state.target_category_scroll_x = 0
        state.item_scroll_y = 0
        state.target_item_scroll_y = 0
        state.list_slide_x = 0
        state.list_slide_alpha = 1
    end

    return state
end

return xmb_state
