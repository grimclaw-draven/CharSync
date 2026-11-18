# CharSync

[English](../README.md) · [Deutsch](de.md) · [Français](fr.md) · [Español](es.md) · [Português](pt-BR.md) · [Italiano](it.md) · [Русский](ru.md) · [한국어](ko.md) · [简体中文](zh-CN.md) · [繁體中文](zh-TW.md)

Configura un personaggio come preferisci e dai le stesse impostazioni a tutti gli altri personaggi. CharSync ti mostra, impostazione per impostazione, cosa cambierà (prima → dopo) e cosa fa ogni modifica, così puoi escludere tutto ciò che non vuoi.

Per **WoW Forever**. Nella lingua del tuo client di gioco: inglese, tedesco, francese, spagnolo, portoghese, italiano, russo, coreano e cinese (semplificato e tradizionale).

## Come funziona

1. Accedi con il personaggio le cui impostazioni devono valere per tutti, apri `/charsync` e clicca su **“Salva come modello generale”**.
2. Per macro e barre delle azioni, salva un **modello di classe** una volta per classe: vanno solo ai personaggi della stessa classe.
3. Quando accede un altro personaggio, CharSync apre una finestra di controllo: ogni differenza con prima → dopo e una spiegazione. Togli la spunta a ciò che non vuoi, poi clicca su **“Applica selezionati”**.

Un addon non può scrivere i file degli altri personaggi, quindi il modello viene salvato per tutto l'account e applicato all'accesso di ciascun personaggio.

## Cosa può sincronizzare

- Le opzioni dell'interfaccia che WoW salva per personaggio (barre delle azioni aggiuntive, indicatore risorse personali, livello missioni, opzioni dei riquadri incursione, mappa del mondo, minimappa)
- Le finestre della chat (nome, dimensione carattere, sfondo, tipi di messaggi, canali) e i colori della chat
- La disposizione attiva della Modalità modifica
- L'assegnazione tasti
- Quali addon sono attivi
- I profili degli addon che salvano le impostazioni con la libreria Ace3
- Macro del personaggio e barre delle azioni, solo per la stessa classe
- Posizioni delle finestre (finestre spostate, di WoW e degli addon) e posizioni dei pulsanti della minimappa

Grafica, audio, la maggior parte delle opzioni dell'interfaccia e quasi tutte le impostazioni degli addon in WoW valgono comunque per tutto l'account.

## Opzioni

- Attiva o disattiva intere sezioni.
- Togli la spunta a una singola impostazione per non sincronizzarla mai più (per tutti i personaggi).
- Salva un modello automaticamente (disattivato di default): una volta al minuto e alla disconnessione, solo se qualcosa è cambiato.
- Applica i nuovi modelli senza chiedere.
- Sezione “Impostazioni dell'account” (disattivata di default): spuntata, ogni modifica alle impostazioni valide per tutti i personaggi (impostazioni degli addon e opzioni di WoW dell'account) compare con il valore precedente – accettala o ripristinala una per una.
- Ripristina ogni voce singolarmente. Sul personaggio modello le modifiche dal salvataggio vanno una per una nel modello (**«Nel modello»**). L'ultima applicazione si può annullare (**«Annulla»**).
- Comprimi le sezioni; la spunta nell'intestazione spunta tutto ciò che contiene.
- **«Impostazioni escluse»** elenca tutto ciò che hai escluso – spuntalo per recuperarlo.

Comandi: `/charsync`, `/charsync save`, `/charsync saveclass`, `/charsync apply`, `/charsync icon` (riporta il pulsante della minimappa)
