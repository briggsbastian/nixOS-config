_: {
  # User-level nixpkgs overlays, picked up by impure evals (`nix-shell -p`,
  # `nix-build` without a flake). Does NOT affect the system flake build.
  # rpcs3: default glew is built with GLEW_EGL=ON, which drops the GLX entry
  # points (__glewXSwapIntervalEXT etc.) rpcs3's GL backend links against.
  xdg.configFile."nixpkgs/overlays/rpcs3-glew.nix".text = ''
    final: prev: {
      rpcs3 = prev.rpcs3.override {
        glew = prev.glew.override { enableEGL = false; };
      };
    }
  '';
}
