class_name CampaignEndings
extends RefCounted

## The epilogue on the campaign-over screen (main.gd::_show_victory_modal). Original prose in
## the spirit of the closing beats of the original SWBF2 Galactic Conquest endings — each
## side's victory reads as its own faction's story, and a defeat is told from the loser's
## chair. `{cap}` is the fallen capital's name. Pure text: no game rules live here.

const VICTORY := {
	Faction.REPUBLIC: "The last Separatist droid falls silent over {cap}. In the Senate, Chancellor Palpatine declares the Clone Wars over and the Republic secure, and the Grand Army stands down to cheering crowds. A new era of peace across the galaxy has begun.",
	Faction.SEPARATIST: "{cap} burns. With the Republic's war machine broken, the Confederacy proclaims a new age of independent systems and the Senate's fractured remnants acquiesces to Separatist terms. With the Jedi now on the run and hunted down as criminals, the galaxy falls under the decisive rule of the Sith.",
	Faction.EMPIRE: "{cap}, the Rebellion's last stronghold, goes dark. Imperial banners rise over the ashes of the Alliance across the galaxy. The Emperor's armies stand unchallenged. With the completion of the Death Star, all systems bow before the unlimited power of the Empire.",
	Faction.REBELLION: "With the {cap} destroyed, the Empire's grip breaks. Imperial armies across the galaxy surrender and the people take to the streets. The Emperor's dream is dead, and the Rebel Alliance has given the galaxy back its freedom. Finally, light begins to shine from of the darkness.",
	Faction.FIRST_ORDER: "{cap} lies in ruins and with it, the Resistance finally breaks. From the ashes of the Empire the First Order rises unopposed, and the galaxy kneels to the will of its Supreme Leader.",
	Faction.RESISTANCE: "The First Order's power breaks with the destruction of {cap}. Across the galaxy the spark becomes a fire: worlds rise, fleets defect, and the tyranny built on the ashes of the Empire crumbles. The Resistance endures, and hope with it.",
}

const DEFEAT := {
	Faction.REPUBLIC: "{cap} has fallen to the Separatists. The Senate flees, the Grand Army's strength dwindles and fades, and the Republic — a thousand years old — ends not with a vote but with the silence of Sith rule.",
	Faction.SEPARATIST: "{cap} falls. The droid armies stop where they stand, the Confederacy's leaders scatter, and the Republic celebrates a victory for order — though not everyone believes this war was ever meant to be won.",
	Faction.EMPIRE: "{cap} has been destroyed by the Rebellion. The Emperor's fleets are scattered and his grip loosens world by world. The Empire's long shadow over the galaxy is lifted at last as Rebellion spreads across the galaxy.",
	Faction.REBELLION: "{cap} has fallen. The Alliance's fleets are hunted down one by one and the Empire's boot settles on the galaxy once more. The Rebellion survives only as a rumour whispered in the dark before even that becomes a distant memory.",
	Faction.FIRST_ORDER: "{cap} is destroyed, and the First Order's grand design with it. Its fleets are scattered, its Supreme Leader's name is a curse across the galaxy, and the Resistance's fires burn brighter than ever.",
	Faction.RESISTANCE: "{cap} has fallen. The Resistance's last ships scatter into the dark and the First Order's boot settles over a silent galaxy. The embers of hope are finally snuffed out, and all that remains is ash.",
}


## `winner` took the enemy capital `cap`. `viewer_won`: true when the person reading it is the
## winner (VICTORY screen), false for the loser's DEFEAT screen; in two-player, always true
## (the winner's story is what both players see). `loser` is only used for the defeat text.
static func epilogue(winner: StringName, viewer_won: bool, cap: String) -> String:
	var table: Dictionary = VICTORY if viewer_won else DEFEAT
	var key: StringName = winner if viewer_won else Faction.opponent(winner)
	var text: String = table.get(key, "%s has fallen." % "{cap}")
	return text.replace("{cap}", cap)
