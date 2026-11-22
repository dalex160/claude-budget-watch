# Budget Guard — application Mac native avec installation guidée

Date : 2026-11-22 · Statut : brouillon, en attente d'approbation d'Alexis

## Intention

Budget Guard affiche dans la barre de menu du Mac la consommation de l'abonnement Claude (limite de la semaine). Aujourd'hui c'est un plugin SwiftBar installé via Homebrew. Un ami d'Alexis a essayé de l'installer et a buté sur **chaque** brique : outils développeur Apple trop anciens pour macOS 27 (Homebrew bloque), fenêtre d'installation Apple qui ne s'ouvre pas, SwiftBar qui exige un dossier de plugins et refuse les choix, plugin non branché dans le dossier choisi, aucune fenêtre de connexion (dépend d'un login Claude Code). Verdict d'Alexis : « beaucoup trop compliqué ».

Objectif : **quelqu'un qui utilise rarement un ordinateur installe et fait marcher Budget Guard seul, guidé écran par écran, sans terminal.**

Public : des amis d'Alexis, abonnés **personnels** à Claude (Pro ou Max, pas d'offre entreprise). Certains utilisent Claude Code, d'autres seulement l'application Claude ou le site. Ils se connectent à Claude avec Google ou avec leur adresse mail (on ne sait pas lesquels : il faut les deux).

## Objectifs

- Télécharger → double-cliquer → un assistant guide jusqu'à l'affichage du pourcentage. Aucune commande, aucun Homebrew, aucun SwiftBar, aucun outil développeur Apple.
- Fonctionne pour un utilisateur de l'application Claude ou du site qui n'a jamais installé Claude Code.
- Interface entièrement en français.
- Conserver ce que fait Budget Guard aujourd'hui : pourcentage de la semaine coloré selon le niveau, heure de remise à zéro, alertes à 80 % et 95 %, état de l'usage au-delà du forfait (overage) dans le menu.

## Non-objectifs

- Validation (notarisation) Apple : Alexis ne paie pas les 99 $/an pour l'instant. À réévaluer plus tard.
- Offres entreprise (Team / Enterprise), comptes gratuits (pas de limites exposées).
- Windows, iPhone.
- Historique, graphiques, coûts : c'est le rôle d'autres outils.

## Anti-objectifs (échec même si « ça marche »)

- Une seule étape qui demande le terminal ou un réglage technique.
- Une boîte de dialogue système effrayante non annoncée par l'assistant (ex. demande d'accès au trousseau qui surgit sans explication).
- Déconnecter l'utilisateur de Claude Code ou de Claude en arrière-plan.
- Envoyer des identifiants ou des données d'usage ailleurs que chez Anthropic.

## Contraintes

- **Pas de notarisation** → au premier lancement, macOS refuse d'ouvrir l'app ; il faut passer par Réglages Système > Confidentialité et sécurité > « Ouvrir quand même ». L'assistant ne peut pas guider cette étape (l'app n'est pas encore ouverte). Couverture : une page de téléchargement qui montre ce passage en 3 captures, juste avant le bouton « Télécharger ».
- Certificat disponible : « Apple Development » (pas de Developer ID). Viji, l'autre app d'Alexis, est distribuée de la même façon (cask Homebrew + retrait de la quarantaine) — ce chemin n'est pas réutilisable ici puisqu'on retire Homebrew.
- **Aucune API officielle** d'Anthropic ne donne les limites d'un abonnement personnel. Les deux chemins connus sont internes et peuvent casser sans préavis :
  - site claude.ai, avec la session du navigateur : `GET https://claude.ai/api/organizations` puis `GET https://claude.ai/api/organizations/{orgId}/usage` → `seven_day.utilization` (déjà en %), `seven_day.resets_at` (ISO 8601), `extra_usage`, etc. (source : code de CodexBar, MIT, très maintenu).
  - jeton Claude Code : `GET https://api.anthropic.com/api/oauth/usage` (en-tête `anthropic-beta: oauth-2025-04-20`), mêmes champs.
- Le plugin actuel obtient ses chiffres en envoyant un vrai message d'un jeton à l'API toutes les 2 minutes et en lisant les en-têtes de réponse : ça consomme (un peu) le forfait qu'on mesure. La nouvelle app ne doit plus faire ça.

## Résultats de l'essai jetable (2026-11-22)

Mini-app Swift avec une fenêtre web intégrée (WKWebView), session non persistante, sur macOS 27.2 :

- La page de connexion claude.ai s'affiche normalement, en français, sans blocage anti-robot (Cloudflare). Boutons présents : Google, Apple, e-mail, SSO.
- **« Continuer avec Google » ouvre bien la page de connexion Google** (« Accéder à l'application Claude »), avec l'identité de navigateur par défaut comme avec une identité Safari. Pas d'erreur « navigateur non sécurisé » à ce stade.
- **Non vérifié** (nécessite un vrai compte, donc Alexis) : que Google ne refuse pas après la saisie de l'adresse ; la connexion par code mail ; la lecture effective du pourcentage une fois connecté ; la connexion par code mail d'un compte créé avec Google.

## Approches envisagées

1. **Recommander CodexBar** (app existante, gratuite, open source). Écartée : notarisation non confirmée, réglages et demandes d'accès au trousseau, surtout en anglais, et pour un utilisateur sans Claude Code elle dépend d'un import de cookies du navigateur que sa propre doc dit peu fiable.
2. **Refaire Budget Guard en application Mac native avec assistant** — **choisie par Alexis.** Seule option adaptée à un novice ; coûts : alerte au premier lancement tant qu'il n'y a pas de notarisation, dépendance à des chemins non officiels.
3. **Garder le plugin SwiftBar + un installeur guidé par-dessus.** Écartée : conserve Homebrew, les outils Apple et SwiftBar, donc tous les murs rencontrés.

## Ce qui est décidé

- Application Mac native, vit dans la barre de menu (pas d'icône dans le Dock), en français.
- Distribution : fichier à télécharger (DMG ou zip) depuis une page web simple, avec le guide illustré « Ouvrir quand même ».
- Assistant au premier lancement, pas à pas, qui mène jusqu'à l'affichage du pourcentage.
- Fonctionne pour les utilisateurs de l'application Claude / du site, connexion Google et e-mail.
- Affichage et alertes identiques au plugin actuel (voir Objectifs).

## Propositions de Claude (non validées par Alexis)

- **Un seul chemin de connexion pour tout le monde : la fenêtre de connexion claude.ai intégrée.** Raison : la limite est la même pour tout le compte, donc un utilisateur de Claude Code peut aussi se connecter ainsi ; on évite la demande d'accès au trousseau (effrayante, et à répéter à chaque mise à jour pour une app non notarisée) et le risque de déconnecter Claude Code en rafraîchissant son jeton. Conséquence : on abandonne la lecture du jeton Claude Code.
- La session reste stockée dans le stockage web propre à l'app ; les appels d'usage sont faits **depuis la page claude.ai elle-même** (fenêtre web cachée), pour réutiliser naturellement la session et les cookies anti-robot plutôt que d'extraire le cookie.
- Si la connexion Google est refusée dans la fenêtre : message dans l'assistant « Vous utilisez Google ? Choisissez plutôt "Continuer avec l'e-mail" et entrez votre adresse Gmail, vous recevrez un code » — à condition que l'essai avec Alexis confirme que ça marche.
- Session expirée ou déconnexion : la barre de menu affiche « CC: — » et le menu propose « Se reconnecter », qui rouvre l'étape de connexion de l'assistant.
- Lancement automatique à l'ouverture de session proposé dans l'assistant, coché par défaut.
- Mises à jour automatiques (Sparkle) pour ne pas refaire le passage « Ouvrir quand même » à chaque version.
- Même dépôt GitHub public que le plugin ; le plugin SwiftBar reste disponible pour l'existant (dont Alexis) jusqu'à ce que l'app le remplace.
- Rafraîchissement toutes les 2 minutes, comme aujourd'hui ; en cas d'échec, garder la dernière valeur connue en la grisant.

## Arbitrages de Claude après relecture (à vérifier par Alexis)

- **Ordre de construction** : d'abord un prototype de connexion testé avec Alexis (Google, e-mail, lecture du pourcentage). L'app complète ne démarre que si ce test passe.
- **Plan B si la connexion intégrée échoue** : les données passent par une petite couche « source d'usage » avec deux implémentations possibles — session claude.ai (principale) et jeton Claude Code (secours, pour ceux qui ont Claude Code, avec demande d'accès au trousseau annoncée par l'assistant). Ne jamais rafraîchir soi-même le jeton Claude Code : relire le trousseau seulement, pour ne pas déconnecter Claude Code.
- **Lecture des chiffres** : `seven_day.utilization` est déjà un pourcentage (0–100) ; `resets_at` en ISO 8601 ; `extra_usage` = `is_enabled`, `used_credits`, `monthly_limit`, `currency`. Un refus 429 ou une utilisation ≥ 100 % s'affiche « 100 % » en rouge, comme aujourd'hui.
- **Organisation** : la première organisation qui a la capacité « chat » (logique de CodexBar). Compte gratuit (fenêtres nulles) ou offre entreprise : message clair dans l'assistant « Budget Guard fonctionne avec les abonnements Pro et Max ».
- **Signature et mises à jour** : signature avec un certificat auto-signé stable (comme Viji) pour que macOS reconnaisse la même app d'une version à l'autre ; clé de signature des mises à jour (Sparkle, EdDSA) générée sur le Mac d'Alexis et sauvegardée hors OneDrive ; flux de mises à jour publié via GitHub Releases. Les mises à jour installées par Sparkle ne repassent pas par « Ouvrir quand même ».
- **Compatibilité** : macOS 13 minimum, binaire universel (Apple Silicon et Intel), pour couvrir des Mac d'amis plus anciens.
- **Alertes** : même logique que le plugin — une alerte par seuil, réarmée quand le pourcentage repasse sous le seuil ; état conservé entre redémarrages. Notifications refusées : l'app marche sans alertes, et le menu propose « Activer les alertes ».
- **Page de téléchargement** : GitHub Pages du même dépôt ; captures « Ouvrir quand même » prises sur une session utilisateur macOS vierge.

## Parcours de l'assistant (proposition)

1. **Bienvenue** — une phrase sur ce que fait l'app, bouton « Commencer ».
2. **Connexion à Claude** — fenêtre de connexion claude.ai intégrée, avec une ligne d'aide au-dessus. Détection automatique de la réussite.
3. **Vérification** — l'app lit le pourcentage et l'affiche en grand : « Vous avez utilisé 18 % de votre limite de la semaine. Remise à zéro jeudi à 10 h. »
4. **Réglages simples** — « Lancer Budget Guard au démarrage du Mac » (coché), « M'alerter à 80 % et 95 % » (coché) → déclenche la demande d'autorisation des notifications, annoncée juste avant.
5. **Terminé** — flèche vers la barre de menu : « Votre pourcentage est ici. »

## Laissé au constructeur

Structure du code, SwiftUI ou AppKit, format DMG ou zip, hébergement de la page de téléchargement (GitHub Pages proposé), mise en page des écrans, gestion des erreurs réseau, journalisation, version minimale de macOS (au plus bas raisonnable pour des amis peu équipés), tests.

## À valider avec Alexis avant de construire

- Essai réel de connexion (Google, puis e-mail) et lecture du pourcentage — nécessite son compte.
- Les propositions ci-dessus, en particulier l'abandon du jeton Claude Code comme chemin principal.
- Le libellé dans la barre de menu : « CC: 18 % » (actuel, « CC » = Claude Code) ou un libellé plus parlant pour des novices (icône Claude + « 18 % »).
