{ config, ... }:

{ 
  xdg.dataFile."jellyfinmediaplayer/mpv.conf".text = ''
    vo=gpu-next
    hwdec=vaapi
    gpu-api=vulkan
  '';

}
