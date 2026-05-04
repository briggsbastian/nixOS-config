{ ... }:

{
  services.flatpak = {
    enable = true;
    
    remotes = [{
      name = "flathub";
      location = "https://flathub.org/repo/flathub.flatpakrepo";
    }];
    
    packages = [
      #jellyfin media player
      "com.github.iwalton3.jellyfin-media-player"
      #proton-mail
      "me.proton.Mail"
    ];
    
    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };
  };
}
