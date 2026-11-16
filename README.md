# CharSync

[English](README.md) · [Deutsch](readme/de.md) · [Français](readme/fr.md) · [Español](readme/es.md) · [Português](readme/pt-BR.md) · [Italiano](readme/it.md) · [Русский](readme/ru.md) · [한국어](readme/ko.md) · [简体中文](readme/zh-CN.md) · [繁體中文](readme/zh-TW.md)

Set up one character the way you like it – and give every other character the same settings. CharSync shows you, setting by setting, what will change (before → after) and what each change does, so you can leave out anything you don't want.

For **WoW Forever**. In the language of your game client: English, German, French, Spanish, Portuguese, Italian, Russian, Korean and Chinese (simplified and traditional).

## How it works

1. Log in with the character whose settings should apply to all, open `/charsync` and click **"Save as general template"**.
2. For macros and action bars, save a **class template** once per class – they only go to characters of the same class.
3. When another character logs in, CharSync opens a review window: every difference with before → after and an explanation. Untick what you don't want, then click **"Apply ticked"**.

An addon cannot write files of other characters, so the template is stored account-wide and applied when each character logs in.

## What it can sync

- Interface options WoW stores per character (extra action bars, personal resource display, quest level, raid frame options, world map, minimap)
- Chat windows (name, font size, background, message types, channels) and chat colors
- The active Edit Mode layout
- Key bindings
- Which addons are enabled
- Profiles of Ace3 addons (AtlasLoot, Questie, SilverDragon …)
- MyCharForever settings, including the minimap button position
- Character macros and action bars – same class only

Graphics, sound, most interface options and almost all addon settings are account-wide in WoW anyway.

## Options

- Turn whole sections on or off.
- Untick a single setting to never sync it again (for all characters).
- Make a character the template character: it updates the template every time it logs out.
- Apply new templates without asking.

Commands: `/charsync`, `/charsync save`, `/charsync saveclass`, `/charsync apply`
