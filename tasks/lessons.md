# Leçons — Budget Guard

- **Installation pour des non-techniciens : chaque dépendance est un mur.** Avant de donner une procédure à quelqu'un, la dérouler mentalement sur un Mac vierge (Homebrew, outils développeur Apple, SwiftBar, login Claude Code). Ne jamais livrer une procédure terminal à un novice ; viser télécharger → double-cliquer.
- **Ne jamais faire supprimer un outil existant avant d'avoir le remplaçant en main.** Faire lancer `rm -rf` sur les Command Line Tools avant que `xcode-select --install` ait réellement abouti a laissé le Mac sans outils du tout. Mettre à jour d'abord (Mise à jour de logiciels / `softwareupdate`), supprimer seulement si nécessaire.
- **SwiftBar n'a pas de dossier de plugins par défaut** : il le demande au premier lancement. Tout script qui « branche » un plugin doit lire `defaults read com.ameba.SwiftBar PluginDirectory` au lieu de supposer un chemin.
