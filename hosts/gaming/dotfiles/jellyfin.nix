{ config, ... }:

{ 
  xdg.dataFile."jellyfinmediaplayer/mpv.conf".text = ''
    vo=gpu
    hwdec=no
  '';

}
