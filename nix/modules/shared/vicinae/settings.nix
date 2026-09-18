{
  close_on_focus_loss = true;
  global_shortcuts.toggle = "super+control+space";
  keybinding = "vim";
  telemetry.system_info = false;
  theme.light.name = "elementary-light";

  providers = {
    browser-extension.enabled = false;
    calculator.preferences.backend = "numen";
    core = {
      enabled = false;
      entrypoints = {
        "search-emojis".enabled = true;
        store.enabled = true;
      };
    };
    developer.enabled = false;
    manage-shortcuts.enabled = false;
  };
}
