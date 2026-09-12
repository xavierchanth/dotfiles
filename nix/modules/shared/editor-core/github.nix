{pkgs, ...}: {
  programs.gh = {
    enable = true;
    extensions = [ pkgs.gh-stack ];
    # Preserve the existing credential configuration; gh authentication remains local.
    gitCredentialHelper.enable = false;
    settings = {
      git_protocol = "https";
      editor = "";
      prompt = "enabled";
      prefer_editor_prompt = "disabled";
      pager = "";
      aliases.co = "pr checkout";
      http_unix_socket = "";
      browser = "";
      color_labels = "disabled";
      accessible_colors = "disabled";
      accessible_prompter = "disabled";
      spinner = "enabled";
    };
  };
}
