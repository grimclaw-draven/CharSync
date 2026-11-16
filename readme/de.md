# CharSync

[English](../README.md) · [Deutsch](de.md) · [Français](fr.md) · [Español](es.md) · [Português](pt-BR.md) · [Italiano](it.md) · [Русский](ru.md) · [한국어](ko.md) · [简体中文](zh-CN.md) · [繁體中文](zh-TW.md)

Einen Char so einstellen, wie man es mag – und alle anderen Chars bekommen dieselben Einstellungen. CharSync zeigt für jede Einstellung, was sich ändert (vorher → nachher) und was die Änderung bewirkt. So kannst du alles weglassen, was du nicht haben willst.

Für **WoW Forever**. In der Sprache deines Spiels: Englisch, Deutsch, Französisch, Spanisch, Portugiesisch, Italienisch, Russisch, Koreanisch und Chinesisch (vereinfacht und traditionell).

## So funktioniert es

1. Mit dem Char einloggen, dessen Einstellungen für alle gelten sollen, `/charsync` öffnen und **„Als allgemeine Vorlage speichern“** klicken.
2. Für Makros und Aktionsleisten einmal je Klasse eine **Klassen-Vorlage** speichern – sie gehen nur an Chars derselben Klasse.
3. Loggt sich ein anderer Char ein, öffnet CharSync ein Prüffenster: jede Abweichung mit vorher → nachher und Erklärung. Haken entfernen, was du nicht willst, dann **„Angehakte übernehmen“**.

Ein Addon kann keine Dateien anderer Chars schreiben. Die Vorlage liegt deshalb accountweit und wird beim Login des jeweiligen Chars übernommen.

## Was übertragen werden kann

- Interface-Optionen, die WoW pro Char speichert (zusätzliche Aktionsleisten, persönliche Ressourcenanzeige, Questlevel, Raidframe-Optionen, Weltkarte, Minimap)
- Chatfenster (Name, Schriftgröße, Hintergrund, Nachrichtenarten, Kanäle) und Chatfarben
- Das aktive Edit-Mode-Layout
- Tastenbelegung
- Welche Addons aktiviert sind
- Profile von Ace3-Addons (AtlasLoot, Questie, SilverDragon …)
- Einstellungen von MyCharForever, auch die Position des Minimap-Icons
- Charakter-Makros und Aktionsleisten – nur gleiche Klasse

Grafik, Sound, die meisten Interface-Optionen und fast alle Addon-Einstellungen gelten in WoW ohnehin accountweit.

## Optionen

- Ganze Bereiche an- oder ausschalten.
- Einzelne Einstellung abwählen = sie wird nie mehr synchronisiert (für alle Chars).
- Einen Char zum Vorlage-Char machen: Er aktualisiert die Vorlage bei jedem Ausloggen.
- Neue Vorlagen ohne Nachfrage übernehmen.

Befehle: `/charsync`, `/charsync save`, `/charsync saveclass`, `/charsync apply`
