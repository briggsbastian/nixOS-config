# hosts/lan/hacktop/minecraft-prune.nix
#
# Retention for the world archives minecraft-backup.nix writes to the NAS.
# Split out of that file for two reasons:
#
#   1. It is the part most likely to be wrong in a way nothing notices. A
#      backup that fails is loud (MinecraftBackupStale); a retention rule that
#      deletes one archive too many is silent until the night you need the one
#      it took. So it lives in its own file, takes its inputs as arguments, and
#      has its own hermetic check (tests/minecraft-prune.nix).
#
#   2. A second world is coming (All the Mods 10). Directory, filename prefix
#      and the three tier counts are all parameters, so the second server gets
#      the same, already-tested rotation by calling this with a different
#      prefix rather than by copy-pasting a `ls | tail | xargs rm` pipeline.
#
# Policy is grandfather-father-son:
#
#     daily   the newest N archives, whatever their dates
#     weekly  the newest archive in each of the W newest ISO-week buckets
#             that are STRICTLY OLDER than the newest archive's own week
#     monthly the same, over calendar-month buckets
#
# The "strictly older" clause is the whole trick and the reason this is not
# just borg's --keep-weekly. Without it, with weekly=1, the weekly slot lands
# on the newest archive in the directory - which is already a daily - and the
# tier buys exactly nothing. With it, the weekly is always the previous week's
# last archive, the monthly is always the previous month's last archive, and
# both roll forward on their own as the calendar turns, because the archive
# that will become next month's monthly is still a daily on the day the month
# ticks over. Getting that wrong pins the monthly on one ever-ageing file
# forever, which looks fine in `ls` and is worthless.
#
# TWO PROPERTIES THIS FILE EXISTS TO PRESERVE:
#
#   * .partial is invisible here. In-flight archives are written as
#     `<dir>/.<prefix>-<ts>.tar.age.partial`; the candidate list is built with
#     a SHELL GLOB, and shell globs do not match dotfiles. A truncated archive
#     must never be selectable by retention in either direction - neither kept
#     as though it were complete, nor counted as surplus and deleted.
#
#   * "Current" is the newest ARCHIVE's bucket, not the wall clock, so this is
#     a pure function of the directory listing. A dry run and the real run an
#     hour later agree; the test can pin an exact keep-set; and a week of
#     failed backups makes the tiers keep MORE history rather than sliding the
#     window off the end of what is actually there.
{ pkgs }:

pkgs.writeShellApplication {
  name = "minecraft-prune";
  runtimeInputs = [ pkgs.coreutils ]; # date, sort, stat, rm

  text = ''
    # Both the sort and the `[[ a < b ]]` bucket comparisons below are string
    # comparisons that must be byte order. Under a UTF-8 locale, collation is
    # free to ignore punctuation - which for "2026-33" vs "2026-34" happens to
    # come out the same, and for some future name format would not. Pinning it
    # costs nothing and removes the class.
    export LC_ALL=C

    usage() {
      cat >&2 <<'EOF'
    usage: minecraft-prune [-n] <dir> <prefix> <daily> <weekly> <monthly>

      -n, --dry-run   report what would go; delete nothing.

    Grandfather-father-son retention over <dir>/<prefix>-YYYYMMDD-HHMMSS.tar.age.
    EOF
      exit 2
    }

    dry=0
    case "''${1-}" in
      -n | --dry-run)
        dry=1
        shift
        ;;
    esac

    [ "$#" -eq 5 ] || usage
    dir=$1
    prefix=$2
    daily=$3
    weekly=$4
    monthly=$5

    for n in "$daily" "$weekly" "$monthly"; do
      case "$n" in
        "" | *[!0-9]*)
          echo "tier counts must be non-negative integers, got '$n'" >&2
          exit 2
          ;;
      esac
    done

    [ -d "$dir" ] || {
      echo "no such directory: $dir" >&2
      exit 1
    }

    # A SHELL GLOB, deliberately - never find(1), whose -name happily matches
    # dotfiles. This is the load-bearing half of the .partial invariant: an
    # in-flight `.<prefix>-<ts>.tar.age.partial` is a dotfile and cannot appear
    # in this array, so nothing below can reason about a truncated archive.
    # Every later loop reads `archives` and nothing else.
    archives=()
    for f in "$dir/$prefix"-*.tar.age; do
      # Also the no-match case: with no matching file bash hands the pattern
      # through literally and this test is what discards it.
      [ -f "$f" ] || continue
      b=''${f##*/}
      case "$b" in
        .* | *.partial) continue ;; # unreachable via the glob; cheap insurance
      esac
      archives+=("$b")
    done

    if [ ''${#archives[@]} -eq 0 ]; then
      echo "prune: no $prefix-*.tar.age under $dir - nothing to do"
      exit 0
    fi

    # The names carry YYYYMMDD-HHMMSS, so a lexical sort IS a chronological
    # one. Sorting by name rather than by mtime on purpose: an mtime is a
    # property of the copy (an NFS round trip, a restore, a stray touch), a
    # name is a property of the backup. Retention must not change because
    # somebody rsynced the directory.
    mapfile -t sorted < <(printf '%s\n' "''${archives[@]}" | sort -r)

    # YYYYMMDD out of "<prefix>-YYYYMMDD-HHMMSS.tar.age". A name that does not
    # parse is KEPT, never deleted - the safe direction for a file we cannot
    # reason about.
    day_of() {
      local stamp=''${1#"$prefix"-}
      stamp=''${stamp%%-*}
      case "$stamp" in
        [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) printf '%s' "$stamp" ;;
        *) return 1 ;;
      esac
    }

    # ISO year-week, both fields zero padded, so string order IS time order
    # and the comparisons below need no arithmetic. Feeding date(1) an
    # unambiguous YYYY-MM-DD rather than a bare 8-digit run, which it is free
    # to interpret however it likes.
    week_of() {
      local d=$1
      date -d "''${d:0:4}-''${d:4:2}-''${d:6:2}" +%G-%V 2>/dev/null
    }

    declare -A keep=()
    declare -A dayOf=()
    declare -A weekOf=()
    declare -A monthOf=()

    # Both halves in the condition on purpose. day_of only checks the SHAPE of
    # the stamp; date(1) is what rejects 20260231. If either says no the file
    # is kept, rather than the script dying under errexit halfway through a
    # prune and leaving the run half-applied.
    for b in "''${sorted[@]}"; do
      if d=$(day_of "$b") && w=$(week_of "$d"); then
        dayOf[$b]=$d
        weekOf[$b]=$w
        monthOf[$b]=''${d:0:6}
      else
        keep[$b]="unparseable name - kept rather than guessed at"
      fi
    done

    # "Now" is the newest archive's own bucket. See the header: this is what
    # makes the whole thing a pure function of the listing.
    newest=''${sorted[0]}
    if [ -n "''${dayOf[$newest]-}" ]; then
      curWeek=''${weekOf[$newest]}
      curMonth=''${monthOf[$newest]}
    else
      curWeek=$(date +%G-%V)
      curMonth=$(date +%Y%m)
    fi

    # Hard floor, asserted before any tier gets a say: the newest archive is
    # never a deletion candidate. A retention policy that can empty the
    # directory is an `rm -rf` with extra steps, and daily=0 or a future change
    # to the tier arithmetic should not be able to reach that state.
    keep[$newest]=''${keep[$newest]-"newest (floor)"}

    # Tier 1: the newest $daily archives, whatever their dates.
    taken=0
    for b in "''${sorted[@]}"; do
      [ "$taken" -lt "$daily" ] || break
      [ -n "''${dayOf[$b]-}" ] || continue # unparseable: already kept, no slot spent
      keep[$b]=''${keep[$b]-"daily"}
      taken=$((taken + 1))
    done

    # Tier 2: weeklies. Newest archive of each of the $weekly newest ISO-week
    # buckets strictly older than curWeek. When the previous week's last
    # archive is still inside the daily window (Mon/Tue, say) this slot lands
    # on a file tier 1 already kept - that is correct and costs nothing; the
    # reason it must still consume the slot is that the alternative, skipping
    # to an older week, quietly makes the retention set bigger than
    # daily+weekly+monthly and the space arithmetic stops being a bound.
    taken=0
    declare -A weekDone=()
    for b in "''${sorted[@]}"; do
      [ "$taken" -lt "$weekly" ] || break
      w=''${weekOf[$b]-}
      [ -n "$w" ] || continue
      [[ "$w" < "$curWeek" ]] || continue
      [ -z "''${weekDone[$w]-}" ] || continue
      weekDone[$w]=1
      keep[$b]=''${keep[$b]-"weekly ($w)"}
      taken=$((taken + 1))
    done

    # Tier 3: monthlies, same shape over calendar months.
    taken=0
    declare -A monthDone=()
    for b in "''${sorted[@]}"; do
      [ "$taken" -lt "$monthly" ] || break
      m=''${monthOf[$b]-}
      [ -n "$m" ] || continue
      [[ "$m" < "$curMonth" ]] || continue
      [ -z "''${monthDone[$m]-}" ] || continue
      monthDone[$m]=1
      keep[$b]=''${keep[$b]-"monthly ($m)"}
      taken=$((taken + 1))
    done

    # Report the whole decision every run, kept and deleted alike. Same
    # argument as the metrics minecraft-backup.nix writes: "the timer is
    # green" and "the right archives are on the NAS" are different claims, and
    # only one of them is worth anything at restore time.
    kept=0
    gone=0
    freed=0
    for b in "''${sorted[@]}"; do
      f=$dir/$b
      if [ -n "''${keep[$b]-}" ]; then
        printf 'prune: keep   %s  (%s)\n' "$b" "''${keep[$b]}"
        kept=$((kept + 1))
        continue
      fi
      sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
      freed=$((freed + sz))
      gone=$((gone + 1))
      if [ "$dry" = 1 ]; then
        printf 'prune: WOULD DELETE %s  (%s bytes)\n' "$b" "$sz"
      else
        printf 'prune: delete %s  (%s bytes)\n' "$b" "$sz"
        rm -f -- "$f"
      fi
    done

    if [ "$dry" = 1 ]; then
      printf 'prune: DRY RUN - %s kept, %s would be deleted, %s bytes would be freed\n' \
        "$kept" "$gone" "$freed"
    else
      printf 'prune: %s kept, %s deleted, %s bytes freed\n' "$kept" "$gone" "$freed"
    fi
  '';
}
