# hosts/lan/hacktop/atmons-ranks.nix
#
# FTB Ranks policy for the ATMons server, generated into
# world/serverconfig/ftbranks/ranks.snbt (see minecraft.nix).
#
# Why this needs no extra mods: the pack already ships FTB Ranks, and on
# NeoForge the permission chain is
#   Cobblemon -> ForgePermissionValidator -> NeoForge PermissionAPI -> FTB Ranks
# (verified in the shipped jars: CobblemonNeoForge.class references
# ForgePermissionValidator and registers nodes via PermissionGatherEvent;
# ftb-ranks ships neoforge/PermissionAPIWrapper.class). So a rank can grant a
# Cobblemon command to a player who is not an operator at all.
#
# GRANT-ONLY, NEVER BLANKET-DENY. FTB Ranks supports `command: false` to deny
# everything and re-allow selectively. We deliberately do not: on a 371-mod
# pack that would silently break legitimate level-0 commands across dozens of
# mods with no way to enumerate them. Granting only named nodes means the
# privilege surface is exactly this file and nothing else - which is what makes
# "nothing an op can do" true by construction rather than by hope.
#
# Two node spellings are granted per command on purpose. NeoForge's
# PermissionNode is namespaced (a ResourceLocation), and it is not settled from
# the outside whether FTB Ranks matches it as "cobblemon.command.checkspawns"
# or "command.checkspawns". Unknown nodes are ignored, so granting both costs
# nothing and saves a deploy round-trip. Once in-game testing shows which form
# actually matched, prune the other.
#
# SNBT is NBT with syntax sugar: unquoted keys (dots included - this is how
# FTB's own documented example writes ftbranks.name_format), bare true/false,
# quoted strings, and '#' comments. NOT '//' - checked against the pack's own
# config/ftbultimine-server.snbt. It is whitespace-insensitive; the tabs below
# are purely so the file reads well when catted on the server.
{ pkgs, lib }:

let
  # Legible on the dark chat background. Black (&0) is deliberately absent - it
  # is unreadable in chat, and offering it is a support ticket waiting to
  # happen. This list is the single source of truth: it generates both the
  # colour ranks below and the /color command's argument whitelist, so the two
  # cannot drift apart.
  colours = [
    {
      id = "red";
      code = "c";
    }
    {
      id = "gold";
      code = "6";
    }
    {
      id = "yellow";
      code = "e";
    }
    {
      id = "green";
      code = "a";
    }
    {
      id = "dark_green";
      code = "2";
    }
    {
      id = "aqua";
      code = "b";
    }
    {
      id = "blue";
      code = "9";
    }
    {
      id = "pink";
      code = "d";
    }
    {
      id = "purple";
      code = "5";
    }
    {
      id = "white";
      code = "f";
    }
    {
      id = "gray";
      code = "7";
    }
  ];

  # Minecraft's formatting codes share the same &-prefixed namespace as the
  # colours, so one name_format can carry both. Each code needs its OWN
  # ampersand: "&6l" is a literal letter l in gold, "&6&l" is bold gold. That
  # mistake is invisible until you look at a name in game, hence this note.
  #
  # "magic" (&k) is the scrambling-glyph effect. Included because it was asked
  # for, but it renders a name unreadable, which on an open server makes
  # moderation harder - you cannot read who you are about to ban.
  styles = [
    {
      id = "plain";
      code = "";
    }
    {
      id = "bold";
      code = "l";
    }
    {
      id = "italic";
      code = "o";
    }
    {
      id = "underline";
      code = "n";
    }
    {
      id = "magic";
      code = "k";
    }
  ];

  # Colour and style cannot be two independent ranks: FTB Ranks resolves a node
  # to the highest-power rank that defines it, so two ranks both setting
  # ftbranks.name_format would mean one silently wins and the other vanishes.
  # The combinations are therefore materialised as one rank each - cheap, since
  # nix writes them. "plain" keeps the bare color_<colour> name, so any rank
  # already assigned in players.snbt stays valid.
  combos = lib.concatMap (
    c:
    map (s: {
      colour = c.id;
      style = s.id;
      rank = "color_${c.id}" + lib.optionalString (s.id != "plain") "_${s.id}";
      format = "&${c.code}" + lib.optionalString (s.code != "") "&${s.code}";
    }) styles
  ) colours;

  # Cobblemon commands that only read, or rename the player's own things. None
  # can create, edit or heal a Pokemon, so none is an economy or progression
  # lever. Names taken from the CobblemonPermissions string table in the
  # shipped jar, so these are real nodes rather than guesses.
  cobblemonSafe = [
    "command.checkspawns"
    "command.pokedex"
    "command.pcsearch"
    "command.querylearnset"
    "command.boxcount"
    "command.renamebox"
    "command.spectatebattle"
  ];

  # Deliberately NOT granted, recorded so the omission reads as a decision
  # rather than an oversight: command.givepokemon, command.spawnpokemon,
  # command.spawnallpokemon, command.giveallpokemon, command.pokemonedit,
  # command.healpokemon, command.getnbt, command.cobblemonconfig.reload,
  # command.npcedit, command.runmolang.

  # FTB Essentials quality-of-life. setwarp/delwarp are absent on purpose:
  # warps are usable but not creatable, so a player cannot mint a public
  # teleport into someone else's base.
  essentialsSafe = [
    "home"
    "sethome"
    "delhome"
    "listhomes"
    "back"
    "spawn"
    "rtp"
    # Player-to-player teleports are consent-based, so the grief risk is lower
    # than warps: nobody arrives anywhere without the destination agreeing.
    "tpa"
    "tpahere"
    "tpaccept"
    "tpdeny"
    "warp"
    "listwarps"
  ];

  # Cobblemon namespaces its already-dotted node; FTB Essentials' docs write
  # the bare "command.home" while its jar namespaces under "ftbessentials".
  # Hence two different second spellings.
  playerNodes =
    lib.concatMap (n: [
      n
      "cobblemon.${n}"
    ]) cobblemonSafe
    ++ lib.concatMap (n: [
      "command.${n}"
      "ftbessentials.${n}"
    ]) essentialsSafe;

  # Explicit \t and \n rather than Nix indented strings: interpolating a
  # generated multi-line block into an '' '' string makes the emitted
  # indentation depend on Nix's common-prefix stripping, which is a silent
  # correctness trap. This way the output is exactly what is written here.
  grantLines = lib.concatMapStrings (n: "\t\t${n}: true\n") playerNodes;

  colourRanks = lib.concatMapStrings (c: ''
    	${c.rank}: {
    		name: "Name: ${c.colour} ${c.style}"
    		power: 100
    		ftbranks.name_format: "<${c.format}{name}&r>"
    	}
  '') combos;

  ranksSnbt = pkgs.writeText "ranks.snbt" (
    ''
      # Generated by hosts/lan/hacktop/atmons-ranks.nix - DO NOT EDIT IN GAME.
      # nix-minecraft re-copies this file from the store on every server start,
      # so live edits (/ftbranks create, /ftbranks node) are reverted at the
      # next restart. Rank MEMBERSHIP is a separate file: players.snbt is left
      # unmanaged, so /ftbranks add persists.
      {
      	# Everyone, including brand-new joins. always_active is FTB Ranks'
      	# built-in "applies to every player" condition.
      	player: {
      		name: "Player"
      		power: 1
      		condition: "always_active"
    ''
    + grantLines
    + ''
      		# Picking your own name colour is cosmetic and grants nothing in
      		# world, so everyone gets it. Move this line into `trusted` below to
      		# make /color a reward again - the command reads this node, so that
      		# one move is the whole change.
      		command.color: true
      	}

      	# Manually granted with: /ftbranks add <player> trusted
      	# Currently grants nothing: /color moved to `player` above. Kept defined
      	# because players.snbt already references it, and deleting a rank out
      	# from under its members is a worse kind of tidy. It is the obvious
      	# place to hang a future perk.
      	trusted: {
      		name: "Trusted"
      		power: 50
      	}

      	# One rank per colour+style combination, assigned by /color (see
      	# atmons-color.js). Power 100 so name_format outranks `player`; each
      	# carries nothing but the format, so being recoloured can never change
      	# what a player is allowed to do.
    ''
    + colourRanks
    + ''

      	# Operators. Deliberately grants nothing: an op already bypasses every
      	# permission check, so nodes here would be noise. It exists so
      	# /ftbranks list_all_ranks shows the whole hierarchy, and it sets no
      	# name_format so an op's chosen /color still shows.
      	admin: {
      		name: "Admin"
      		power: 1000
      		condition: "op"
      	}
      }
    ''
  );
in
{
  inherit combos ranksSnbt;
}
