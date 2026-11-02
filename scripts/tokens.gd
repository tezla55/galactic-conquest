class_name Tokens
extends RefCounted

## The look: a tactical holoprojector. Everything reads as light cast into a dark room —
## thin strokes, cool ambient glow, colour used only where it carries information. Nothing
## here is decorative for its own sake.
##
## Ownership colour is **player-relative, not faction-fixed**: the side the player chose
## always reads blue (FRIENDLY), the enemy always red (HOSTILE), in either campaign.
## main.gd::_owner_color / _campaign_glow apply it (they have `state.player_faction`).

const VOID := Color("06090e")          ## Deepest background (map fallback).
## UI chrome is deliberately **neutral grey/near-black, no hue** — the galaxy is already
## saturated blue and the bars/buttons/panels must not compete with or echo it.
const SURFACE := Color("121214")       ## Panels, popup, modal fills.
const SURFACE_EDGE := Color("2b2c2f")  ## Button fills, hairline borders.
const LANE := Color("22384d")          ## Inactive hyperlanes (in-world — stays blue).
const LANE_ACTIVE := Color("4fc3e8")   ## Traversable this turn (in-world — stays blue).

const FRIENDLY := Color("3d8fd1")   ## the player's side — always blue
const HOSTILE := Color("e8593a")    ## the enemy — always red
const NEUTRAL := Color("6d7889")

## Text is neutral only — near-white, grey, or the one accent (WARNING yellow). No hue
## anywhere else; the galaxy owns blue.
const TEXT := Color("e4e4e6")
const TEXT_DIM := Color("8a8a8d")
const WARNING := Color("e8b23a")   ## the single accent — call-to-action / notices

const SPACE_1 := 4.0
const SPACE_2 := 8.0
const SPACE_3 := 16.0
const SPACE_4 := 24.0
const SPACE_5 := 40.0

## Futura — the Star Wars lettering face. Weight carries importance: HEAVY for the turn
## banner (rendered all-caps), MEDIUM for buttons and modal titles, BOOK for body copy,
## LIGHT for the quiet status line. Each is given the engine default as a fallback in
## main.gd::_init_fonts so glyphs Futura lacks (✦, ⚙, arrows) still render.
const FONT_HEAVY := preload("res://ui/fonts/Futura-Heavy.ttf")
const FONT_BOLD := preload("res://ui/fonts/Futura-Bold.ttf")
const FONT_MEDIUM := preload("res://ui/fonts/Futura-Medium.ttf")
const FONT_BOOK := preload("res://ui/fonts/Futura-Book.ttf")
const FONT_LIGHT := preload("res://ui/fonts/Futura-Light.ttf")
## Trajan Bold — used only for the boot wizard's main "GALACTIC CONQUEST" title.
const FONT_TRAJAN := preload("res://ui/fonts/Trajan-Bold.ttf")

const FONT_SIZE_BASE := 15
const FONT_SIZE_SMALL := 13
const FONT_SIZE_TITLE := 22

const PLANET_RADIUS := 22.0
const RING_WIDTH := 2.0
