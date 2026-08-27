# tests/minecraft-prune.nix
#
# The retention rule in minecraft-prune.nix is the highest-consequence,
# lowest-visibility line in the backup chain. It builds, it evaluates, it
# reviews fine, and the only observable difference between "correct" and "one
# archive too greedy" is which night you still have a world to roll back to.
# Nothing in `nix flake check` would otherwise look at it, for the same reason
# tests/mgmt-backup.nix and tests/minecraft-console.nix exist.
#
# Not a VM test: the thing under test is a pure function from a directory
# listing to a set of unlinks. Feeding it real files in a sandbox exercises it
# completely and costs seconds rather than a boot, and the pruner is written to
# derive "now" from the newest ARCHIVE rather than the wall clock precisely so
# a test can pin exact answers instead of re-deriving them from date(1) and
# proving only that two copies of the same bug agree.
{ pkgs }:

let
  prune = import ../hosts/lan/hacktop/minecraft-prune.nix { inherit pkgs; };
in
pkgs.runCommand "minecraft-prune-test" { nativeBuildInputs = [ prune ]; } ''
  set -euo pipefail

  # Every fixture is a real, non-empty file, so the pruner's stat/size
  # reporting is exercised rather than short-circuited.
  fixture() {
    local d=$1 n
    shift
    rm -rf "$d"
    mkdir -p "$d"
    for n in "$@"; do
      echo "ciphertext" > "$d/$n"
    done
  }

  # -A, so a surviving dotfile (the .partial) is part of the assertion rather
  # than invisible to it.
  expect() {
    local d=$1 got want
    shift
    got=$(cd "$d" && ls -A | sort | tr '\n' ' ')
    want=$(printf '%s\n' "$@" | sort | tr '\n' ' ')
    if [ "$got" != "$want" ]; then
      echo "FAIL in $d"
      echo "  want: $want"
      echo "  got:  $got"
      exit 1
    fi
  }

  # ---------------------------------------------------------------- steady
  # A fortnight-and-more of dailies, i.e. exactly what the NAS holds on the
  # day this policy lands, and the run that reclaims it. Newest is
  # 2026-08-20, ISO week 2026-34, month 202608.
  #
  #   dailies  0820 0819 0818
  #   weekly   newest in a week strictly before 2026-34 -> 0816 (2026-33)
  #   monthly  newest in a month strictly before 202608 -> 0731
  #
  # 0817 is the interesting one: it is the fourth-newest AND in the current
  # week, so nothing has a slot for it. A flat `keep = 3` would delete the
  # same file; the difference between the two policies is 0816 and 0731.
  fixture steady \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-20260818-040000.tar.age \
    atmons-world-20260817-040000.tar.age \
    atmons-world-20260816-040000.tar.age \
    atmons-world-20260815-040000.tar.age \
    atmons-world-20260810-040000.tar.age \
    atmons-world-20260809-040000.tar.age \
    atmons-world-20260801-040000.tar.age \
    atmons-world-20260731-040000.tar.age \
    atmons-world-20260715-040000.tar.age \
    atmons-world-20260630-040000.tar.age

  minecraft-prune steady atmons-world 3 1 1
  expect steady \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-20260818-040000.tar.age \
    atmons-world-20260816-040000.tar.age \
    atmons-world-20260731-040000.tar.age

  # Idempotent: a second run must be a no-op, not a second bite.
  minecraft-prune steady atmons-world 3 1 1
  expect steady \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-20260818-040000.tar.age \
    atmons-world-20260816-040000.tar.age \
    atmons-world-20260731-040000.tar.age

  # ---------------------------------------------------------- THE INVARIANT
  # A run killed mid-tar leaves `.atmons-world-<ts>.tar.age.partial`. Whatever
  # else changes in this file, that must never be reachable by retention: not
  # kept as though it were a real archive, not counted toward a tier, not
  # deleted as surplus. It is a dotfile AND it is outside the *.tar.age
  # pattern, and the pruner rejects it a third time by hand.
  #
  # Also present: a foreign prefix. When the second world lands, the two
  # pruners run over the same directory, and each must be blind to the
  # other's archives.
  fixture partial \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-20260818-040000.tar.age \
    atmons-world-20260817-040000.tar.age \
    atmons-world-20260701-040000.tar.age \
    .atmons-world-20260821-040000.tar.age.partial \
    atm10-world-20260101-040000.tar.age

  minecraft-prune partial atmons-world 3 0 0
  expect partial \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-20260818-040000.tar.age \
    .atmons-world-20260821-040000.tar.age.partial \
    atm10-world-20260101-040000.tar.age

  # And the other direction: the second world's own prune leaves ours alone.
  minecraft-prune partial atm10-world 3 0 0
  expect partial \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-20260818-040000.tar.age \
    .atmons-world-20260821-040000.tar.age.partial \
    atm10-world-20260101-040000.tar.age

  # ------------------------------------------------------------ unparseable
  # A name the date parser cannot read is kept, never guessed at, and never
  # spends a tier slot - deleting a file we cannot reason about is the one
  # unrecoverable direction.
  #
  # Two shapes of unreadable, because they fail at different places:
  # `restored-by-hand` is rejected by the eight-digit pattern, and 20260231 is
  # the right shape but not a date, so only date(1) catches it. That second one
  # would, under errexit, otherwise kill the prune halfway through and leave a
  # run half-applied.
  fixture odd \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-restored-by-hand.tar.age \
    atmons-world-20260231-040000.tar.age \
    atmons-world-20260101-040000.tar.age

  minecraft-prune odd atmons-world 2 0 0
  expect odd \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-restored-by-hand.tar.age \
    atmons-world-20260231-040000.tar.age

  # ---------------------------------------------------------------- dry run
  # The one-off reclaim of the old 14-day set is done by running this with -n
  # first and then without (see MAINTENANCE.md), so "-n deletes nothing" is a
  # load-bearing claim, not a nicety.
  fixture dry \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-20260818-040000.tar.age \
    atmons-world-20260817-040000.tar.age

  minecraft-prune -n dry atmons-world 3 0 0 | tee dry.log
  expect dry \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age \
    atmons-world-20260818-040000.tar.age \
    atmons-world-20260817-040000.tar.age
  grep -q 'WOULD DELETE atmons-world-20260817' dry.log
  grep -q 'DRY RUN' dry.log

  # ------------------------------------------------------- month changeover
  # Documents the known dip rather than pretending it away. On 2026-09-01 the
  # previous month's last archive (0831) is still inside the daily window, so
  # it consumes the monthly slot and July's is released - the horizon is the
  # daily window for a day or two. This is why the header on
  # minecraft-backup.nix says "not a guaranteed 30 days", and why raising
  # keepMonthly to 2 is the fix when there is space for it.
  fixture rollover \
    atmons-world-20260901-040000.tar.age \
    atmons-world-20260831-040000.tar.age \
    atmons-world-20260830-040000.tar.age \
    atmons-world-20260829-040000.tar.age \
    atmons-world-20260731-040000.tar.age

  minecraft-prune rollover atmons-world 3 1 1
  expect rollover \
    atmons-world-20260901-040000.tar.age \
    atmons-world-20260831-040000.tar.age \
    atmons-world-20260830-040000.tar.age

  # keepMonthly = 2 is what makes that a real 30 days: July's survives.
  fixture rollover2 \
    atmons-world-20260901-040000.tar.age \
    atmons-world-20260831-040000.tar.age \
    atmons-world-20260830-040000.tar.age \
    atmons-world-20260829-040000.tar.age \
    atmons-world-20260731-040000.tar.age

  minecraft-prune rollover2 atmons-world 3 1 2
  expect rollover2 \
    atmons-world-20260901-040000.tar.age \
    atmons-world-20260831-040000.tar.age \
    atmons-world-20260830-040000.tar.age \
    atmons-world-20260731-040000.tar.age

  # ----------------------------------------------------------------- floors
  # All tiers zero must still not empty the directory. A retention policy that
  # can is an `rm -rf` with extra steps, and a future edit to the arithmetic
  # should hit this instead of the NAS.
  fixture floor \
    atmons-world-20260820-040000.tar.age \
    atmons-world-20260819-040000.tar.age

  minecraft-prune floor atmons-world 0 0 0
  expect floor atmons-world-20260820-040000.tar.age

  # An empty directory is a no-op, not an error: the very first run on a new
  # world happens before its first archive exists.
  mkdir -p empty
  minecraft-prune empty atmons-world 3 1 1

  # Bad input fails loudly rather than defaulting to something destructive.
  ! minecraft-prune floor atmons-world 3 1 2>/dev/null
  ! minecraft-prune floor atmons-world three 1 1 2>/dev/null
  ! minecraft-prune /nonexistent atmons-world 3 1 1 2>/dev/null

  touch $out
''
