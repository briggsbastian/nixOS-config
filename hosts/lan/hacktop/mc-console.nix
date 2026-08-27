# hosts/lan/hacktop/mc-console.nix
#
# The only supported way to send a command to the ATMons server console.
#
# Since minecraft.nix switched to managementSystem.systemd-socket, the console
# is a FIFO created by minecraft-server-atmons.socket. That makes one mistake
# catastrophic and easy: writing to it with a bare shell redirect
#
#   echo save-all > /run/minecraft/atmons.stdin      # DO NOT DO THIS
#
# creates a REGULAR FILE at that path if the socket unit happens to be down.
# systemd then refuses to start the socket ("path exists and is not a FIFO"),
# so the server never comes back. It builds fine, it reviews fine, and it only
# detonates on a night the server was already down - which is exactly when the
# backup would be the thing to trip it.
#
# So: every writer goes through here. `up` checks the service, the socket AND
# that the path is really a FIFO; `send` refuses unless `up`, and then writes
# with dd conv=nocreat so that even if all three checks lie, the kernel will
# not create a regular file.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  fifo = "/run/minecraft/atmons.stdin";
  unit = "minecraft-server-atmons";

  mcConsole = pkgs.writeShellApplication {
    name = "mc-console";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      fifo=${fifo}

      usage() {
        echo "usage: mc-console up            - is the console writable?" >&2
        echo "       mc-console send <words>  - send one command line" >&2
        exit 2
      }

      # All three conditions matter. The service can be active while the socket
      # is not (and vice versa), and the -p test is the one that actually
      # catches a regular file left behind by a stray redirect.
      console_up() {
        systemctl is-active --quiet ${unit}.service || return 1
        systemctl is-active --quiet ${unit}.socket || return 1
        [ -p "$fifo" ] || return 1
      }

      case "''${1-}" in
      up)
        console_up
        ;;
      send)
        shift
        [ "$#" -ge 1 ] || usage
        if ! console_up; then
          echo "mc-console: console unavailable (service, socket, or FIFO missing)" >&2
          exit 1
        fi
        # conv=nocreat drops O_CREAT, so a missing FIFO is an error rather than
        # a newly created regular file. The timeout guards the other failure
        # mode: opening a FIFO for writing blocks until something is reading,
        # and a wedged JVM would otherwise hang the backup until its stop
        # timeout fires.
        printf '%s\n' "$*" | timeout 10 dd of="$fifo" conv=nocreat status=none
        ;;
      *)
        usage
        ;;
      esac
    '';
  };
in
{
  # Exposed as an option, not just a systemPackages entry, so the backup and
  # restart units can reference the exact store path instead of trusting
  # whatever /run/current-system/sw/bin happens to hold at the time they run.
  options.alcove.mcConsole.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    default = mcConsole;
    description = "Helper for talking to the ATMons server console safely.";
  };

  config.environment.systemPackages = [ mcConsole ];
}
