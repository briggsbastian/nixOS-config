# attic

Modules that are **imported by nothing**. Nix never evaluates anything in here.

This is not a staging area and not a backup — git history already does both jobs.
It exists for the rare module whose *reasoning* cost more than its code: where the
comments record which obvious approach was tried and why it failed. Digging that
back out of a deleted file is annoying enough that a few kept files are cheaper.

`nix fmt` still walks this directory (treefmt's `projectRootFile` is the flake at
the repo root), so files here must stay formatted or the `formatting` flake check
goes red. That is the only obligation attic files carry.

If a file in here stops being worth reading, delete it. That is what git is for.

## Contents

- `decepticon.nix` — Docker/Compose substrate for PurpleAILAB's Decepticon
  red-team agent. Was `hosts/lan/playground/decepticon.nix` until playground was
  re-imaged with stock Proxmox VE (2026-07). Explains why the stack is *not*
  Nixified into `virtualisation.oci-containers`, and why the launcher must run in
  the foreground rather than under tmux.
