local xmb_actions = {}

function xmb_actions.play_nav_sfx(settings, assets)
    if settings and settings.keytone_enabled then
        assets.play_sfx("nav")
    end
end

function xmb_actions.apply_setting_value(settings, settings_view, browser, xmb, refresh_settings_items)
    local selected = browser.files[xmb.current_item_idx]
    if not selected or not selected.setting_idx then
        return false
    end

    local opt = settings.options[selected.setting_idx]
    if not opt then
        return false
    end

    opt.value = settings_view.selected_option_idx
    settings.apply()
    settings.save()
    refresh_settings_items(true)
    return true
end

return xmb_actions
