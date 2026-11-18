# CharSync

[English](../README.md) · [Deutsch](de.md) · [Français](fr.md) · [Español](es.md) · [Português](pt-BR.md) · [Italiano](it.md) · [Русский](ru.md) · [한국어](ko.md) · [简体中文](zh-CN.md) · [繁體中文](zh-TW.md)

Configurez un personnage comme vous l'aimez – et donnez les mêmes réglages à tous vos autres personnages. CharSync vous montre, réglage par réglage, ce qui va changer (avant → après) et l'effet de chaque changement, pour que vous puissiez laisser de côté tout ce que vous ne voulez pas.

Pour **WoW Forever**. Dans la langue de votre client de jeu : anglais, allemand, français, espagnol, portugais, italien, russe, coréen et chinois (simplifié et traditionnel).

## Fonctionnement

1. Connectez-vous avec le personnage dont les réglages doivent s'appliquer à tous, ouvrez `/charsync` et cliquez sur **« Enregistrer comme modèle général »**.
2. Pour les macros et les barres d'action, enregistrez un **modèle de classe** une fois par classe – ils ne vont qu'aux personnages de la même classe.
3. Quand un autre personnage se connecte, CharSync ouvre une fenêtre de vérification : chaque différence avec avant → après et une explication. Décochez ce que vous ne voulez pas, puis cliquez sur **« Appliquer la sélection »**.

Un addon ne peut pas écrire les fichiers des autres personnages : le modèle est donc enregistré pour tout le compte et appliqué à la connexion de chaque personnage.

## Ce qui peut être synchronisé

- Les options d'interface que WoW enregistre par personnage (barres d'action supplémentaires, affichage des ressources personnelles, niveau des quêtes, options des cadres de raid, carte du monde, minicarte)
- Les fenêtres de discussion (nom, taille de police, fond, types de messages, canaux) et les couleurs de la discussion
- La disposition active du mode Édition
- Les raccourcis
- Les addons activés
- Les profils des addons qui enregistrent leurs réglages avec la bibliothèque Ace3
- Les macros de personnage et les barres d'action – même classe uniquement
- Positions des fenêtres (fenêtres déplacées, de WoW et des addons) et positions des boutons de la minicarte

Les graphismes, le son, la plupart des options d'interface et presque tous les réglages d'addons sont de toute façon communs au compte dans WoW.

## Options

- Activer ou désactiver des sections entières.
- Décocher un réglage pour ne plus jamais le synchroniser (pour tous les personnages).
- Enregistrer un modèle automatiquement (désactivé par défaut) : une fois par minute et à la déconnexion, seulement si quelque chose a changé.
- Appliquer les nouveaux modèles sans demander.
- Section « Réglages du compte » (désactivée par défaut) : une fois cochée, chaque changement des réglages valables pour tous les personnages (réglages d'addons et options de WoW du compte) apparaît avec sa valeur précédente – à accepter ou réinitialiser un par un.
- Réinitialiser chaque entrée séparément. Sur le personnage modèle, les changements depuis l'enregistrement vont un par un dans le modèle (**« Vers le modèle »**). La dernière application peut être annulée (**« Annuler »**).
- Replier les sections ; la case dans l'en-tête coche tout ce qu'elle contient.
- **« Réglages exclus »** liste tout ce que tu as exclu – coche une entrée pour la récupérer.

Commandes : `/charsync`, `/charsync save`, `/charsync saveclass`, `/charsync apply`, `/charsync icon` (fait revenir le bouton de la minicarte)
