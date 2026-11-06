# Sessions Claude Code

Timi peut afficher **un petit Timi par session Claude Code en cours**, qu’elle tourne dans un terminal ou dans Claude Desktop (onglet Code). Chaque petit Timi reflète le statut de sa session : il **t'interpelle** quand la session a besoin de toi, et un clic fait passer le focus sur son terminal (pane herdr, workspace cmux, ou l’app qui l’héberge : Terminal, iTerm2, Ghostty, VS Code…) ou sur sa conversation dans Claude Desktop.

Le grand Timi ne change pas. Les petits Timi se rangent à côté de lui et le suivent : en ligne horizontale quand il est collé en bas ou en haut (coins compris) ou flottant, en colonne verticale quand il est collé au bord gauche ou droit. Comme le grand Timi, ceux de la première ligne se collent au même bord de l’écran avec les mêmes raccords ; leur nom, leur bulle et leur saut passent du côté intérieur.

## Fonctionnement

1. Claude Code exécute la commande d'un hook à chaque événement configuré.
2. Cette commande envoie le JSON de l'événement avec `curl` vers le socket Unix `~/Library/Application Support/Timi/claude-hooks.sock`.
3. Timi met à jour l'état de la session, identifiée par son `session_id`, puis met à jour les petits Timi.

Claude Desktop exécute Claude Code avec le même fichier `~/.claude/settings.json` : les mêmes hooks couvrent ses sessions, sans rien installer de plus. Les états sont identiques ; seul le clic diffère (voir [Clic](#clic)).

La communication est **locale uniquement** : il s'agit d'un socket Unix, pas d'un port TCP. Rien n'écoute sur le réseau, il n'y a pas de conflit de port ni de demande du pare-feu, et seul ton utilisateur macOS peut se connecter au socket (créé en 0600, dans `~/Library` qui est en 0700).

Si Timi est fermé, la connexion est refusée immédiatement. La commande sort alors avec le code 0 grâce à `|| true`, et `-m 1` limite l'attente à une seconde. Claude n'est donc jamais bloqué par Timi. Côté Claude Code, chaque hook a en plus un `timeout` de 5 secondes.

Le nom affiché sous chaque petit Timi est celui du projet : on remonte depuis le dossier de travail jusqu'au dossier contenant `.git`, sinon on prend le nom du dossier courant. L'infobulle indique le projet et le statut en clair.

## Installation

`./scripts/install.sh` installe Timi **et** les hooks. Pour ne gérer que les hooks :

```sh
./scripts/claude-hooks.sh install    # ajoute ou met à jour l’entrée Timi des onze événements, et enveloppe la statusline
./scripts/claude-hooks.sh status     # code de sortie 0 si les onze événements et la statusline sont à jour
./scripts/claude-hooks.sh uninstall  # retire les entrées Timi et restaure ta statusline
```

Le script modifie `~/.claude/settings.json` (ou `$CLAUDE_CONFIG_DIR/settings.json`), hors du repo, avec le `jq` fourni par macOS. Il crée le fichier s’il n’existe pas, refuse un JSON invalide, conserve les autres hooks, ne duplique jamais l’entrée Timi et écrit une sauvegarde `settings.json.bak-timi` avant toute modification. En cas de problème : `mv ~/.claude/settings.json.bak-timi ~/.claude/settings.json`.

L’installation enveloppe aussi ta statusline pour lire les limites d’utilisation (voir [Limites d’utilisation](#limites-dutilisation)).

Les sessions Claude Code déjà ouvertes doivent être relancées pour charger les nouveaux hooks. Pour Claude Desktop, quitter puis rouvrir l’app.

### Entrée installée

Le script ajoute, pour chacun des événements `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `SubagentStart`, `SubagentStop` et `SessionEnd`, une entrée identique à celle-ci (ici `Stop`) :

```json
"Stop": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "curl -s -m 1 --unix-socket \"$HOME/Library/Application Support/Timi/claude-hooks.sock\" -H \"X-Timi-Pid: $PPID\" -H \"X-Timi-Cmux-Workspace: $CMUX_WORKSPACE_ID\" -H \"X-Timi-Cmux-Surface: $CMUX_SURFACE_ID\" -H \"X-Timi-Cmux-Socket: $CMUX_SOCKET_PATH\" -H \"X-Timi-Cmux-Cli: $CMUX_BUNDLED_CLI_PATH\" -H \"X-Timi-Herdr-Pane: $HERDR_PANE_ID\" -H \"X-Timi-Herdr-Socket: $HERDR_SOCKET_PATH\" -H \"X-Timi-Herdr-Cli: $HERDR_BIN_PATH\" --data-binary @- http://timi/claude-hook >/dev/null 2>&1 || true",
        "timeout": 5
      }
    ]
  }
]
```

Les variables cmux et herdr sont vides hors de ces outils : la même entrée sert pour tous les terminaux.

## États

| Statut | Rendu | Événements déclencheurs |
|---|---|---|
| Travaille | Yeux plissés et concentrés qui lisent par saccades, regard levé de temps en temps pour réfléchir, respiration rapide, liseré et halo bleus | `UserPromptSubmit`, `PreToolUse` (hors questions), `PostToolUse`, `PostToolUseFailure`, `SubagentStart` |
| A besoin de toi (urgent) | Sursaut à l'entrée, yeux suppliants qui suivent le curseur, saut toutes les 1,5 s, liseré et halo orange, bulle « ! » | `PermissionRequest` ; `PreToolUse` pour `AskUserQuestion` et `ExitPlanMode` ; `Notification` de type `permission_prompt` ou `elicitation_dialog` |
| A fini, à toi (doux) | Petit rire et frétillement à l'entrée, puis yeux sereins qui suivent le curseur et pulsation d'un point vert | `Stop` ; `Notification` de type `idle_prompt` |
| En attente | Moitié de sa taille, collé à son bord, yeux endormis, immobile hormis un bâillement de temps en temps | `SessionStart` (un `SessionStart` après compactage ne change pas le statut) |

Pendant « Travaille », certains événements déclenchent aussi une brève réaction des yeux : `UserPromptSubmit` → « ah ! », `PostToolUseFailure` → grimace, `SubagentStart` → regard alentour, `PostToolUse` → clin d'œil occasionnel. Les événements arrivent en rafale pendant un tour : la vue espace donc ces réactions de 1,5 à 6 s pour qu'elles restent lisibles. Un événement de sous-agent ne déclenche pas de réaction pendant « A besoin de toi ».

Règles complémentaires :

- Une session est supprimée à l'événement `SessionEnd`.
- Une session inconnue est créée au premier événement reçu.
- Au lancement, Timi lit les fichiers `~/.claude/sessions/<pid>.json` que Claude Code tient pour chaque session ouverte. Les sessions dont le process est vivant apparaissent tout de suite : « Travaille » si le fichier indique `busy`, « En attente » sinon. Ce format n’est pas documenté par Claude Code : un fichier illisible est ignoré, et la session apparaît alors à son prochain événement. Une session bloquée sur une demande n’est reconnue comme urgente qu’à son prochain événement, et le clic ne peut focus son terminal qu’après ce premier événement.
- `SubagentStop` ne change pas le statut : Claude Code termine des agents internes juste après `Stop`, et le tour doit rester fini.
- Un événement d'un sous-agent ne fait jamais repasser une session « A besoin de toi » à « Travaille ». Seul le fil principal lève l'alerte.
- Les autres types de `Notification` sont ignorés.

## Clic

Un clic sur un petit Timi focus le terminal ou la conversation Claude Desktop de la session :

- **Claude Desktop** : si le fichier `~/.claude/sessions/<pid>.json` de la session indique `"entrypoint": "claude-desktop"`, Timi ouvre `claude://code/continue?session=<hostSessionId>`. Claude Desktop passe alors au premier plan sur cette conversation. Ce lien n’est pas documenté : c’est celui qu’utilise le menu du Dock de Claude Desktop (« Continue Last Claude Code Session »). S’il change, le clic n’aura plus d’effet sur ces sessions.
- **herdr** : si la session tourne dans un pane herdr, Timi lance `herdr agent focus <pane>` avec le pane et le socket transmis par le hook. herdr bascule alors sur le workspace, l’onglet et le pane de l’agent.
- **cmux** : Timi lance la CLI cmux (`select-workspace`) avec le workspace et le socket transmis par le hook, puis active cmux. Quand herdr tourne dans cmux, les variables cmux sont héritées et cette étape amène au premier plan le workspace cmux qui héberge herdr.
- **Autres terminaux et éditeurs** (Terminal, iTerm2, Ghostty, Warp, VS Code, Cursor…) : Timi remonte l’arbre des processus depuis le PID de `claude` (`sysctl`, sans permission) jusqu’à la première app macOS ordinaire, et la passe au premier plan. Seule l’app est activée : choisir sa fenêtre ou son onglet demanderait des Apple Events et une permission d’automatisation.

Un herdr lancé dans un autre terminal que cmux reçoit le focus du pane, puis ce terminal est activé de la même façon, tant que le serveur herdr reste un descendant du terminal qui l’a lancé.

Si aucune app n’est trouvée dans l’arbre (session dans tmux, dont le serveur est détaché du terminal, ou serveur herdr rattaché depuis un autre terminal), Timi active cmux s’il est ouvert, sinon rien.

Le focus passe par un processus lancé directement, sans Apple Events : aucune permission d'automatisation n'est demandée.

## Couleur par projet

Un clic droit (ou ⌃-clic) sur un petit Timi ouvre une palette de neuf noirs teintés pour son corps : Noir (par défaut), Ardoise, Indigo, Violet, Prune, Bordeaux, Brun, Forêt, Sarcelle. Le choix vaut pour le projet (le nom affiché sous le petit Timi), donc pour toutes ses sessions présentes et futures, et il est mémorisé dans les préférences (`projectColors`). Les teintes restent très sombres : le petit Timi reste noir au premier coup d’œil, avec juste un reflet de la couleur du projet.

## Limites d'utilisation

Au bout de la rangée des petits Timi, une **petite silhouette noire**, pareille à celle d’un petit Timi, montre l’usage de ton compte Claude sur un cadran coupé en deux, sans chiffres, avec les yeux de Timi au centre : le demi-cercle du haut pour la fenêtre de 5 h, celui du bas pour la semaine. Chacun se remplit de gauche à droite. Le haut est vert, le bas bleu ; ils passent à l’orange dès 75 % et au rouge dès 90 %, et la silhouette prend alors un halo rouge. Le libellé sous la silhouette indique le temps avant la réinitialisation de la fenêtre de 5 h, et l'infobulle détaille les deux limites.

La jauge n’apparaît que s'il y a au moins un petit Timi **et** une lecture des limites. Seuls les comptes Pro et Max en fournissent, et seulement après la première réponse de l'API dans une session.

### Pourquoi la statusline

Claude Code ne transmet `rate_limits` (`five_hour` et `seven_day`, chacun avec `used_percentage` et `resets_at` en secondes epoch) qu'à la **statusline** : les hooks ne le reçoivent pas. L'installation remplace donc la commande `statusLine` de `settings.json` par un petit script Timi, `~/Library/Application Support/Timi/statusline.sh`, qui :

1. lit le JSON de la statusline sur stdin, octet pour octet ;
2. l'envoie en arrière-plan à Timi (`POST http://timi/claude-statusline` sur le même socket Unix, `-m 1`, sans jamais bloquer ni afficher d'erreur) ;
3. relance ta commande d'origine avec exactement la même entrée : **sa sortie et son code de sortie restent identiques**. Si tu n'avais pas de statusline, le script n'affiche rien.

L'ancienne commande est sauvegardée dans `~/Library/Application Support/Timi/statusline-original` avant d'être remplacée. Les autres champs de `statusLine` (`padding`, `refreshInterval`…) sont conservés. Réinstaller est idempotent et n'écrase jamais cette sauvegarde par le script Timi. `claude-hooks.sh uninstall` restaure la commande d'origine (ou retire `statusLine` s'il n'y en avait pas) puis supprime les deux fichiers ; si tu as changé ta statusline entre-temps, elle n'est pas touchée.

Un `/statusline` ultérieur ou toute autre modification de `statusLine` retire le script Timi : les jauges ne se mettent alors plus à jour. Relance `./scripts/claude-hooks.sh install` pour le remettre ; ta nouvelle commande devient la commande d'origine.

### Données du compte

Les limites sont celles du compte, pas d'une session. La lecture la plus récente gagne : dans une même fenêtre on garde le pourcentage le plus haut, et une fenêtre plus récente remplace l'ancienne. Passé `resets_at`, la jauge repasse à 0 sans attendre de nouvelle lecture. La dernière lecture est conservée entre deux lancements (`UserDefaults`).

## Test manuel sans Claude

Avec Timi lancé, ces trois commandes simulent une session dans le terminal fish. `$fish_pid` remplace `$$`, qui n'existe pas dans fish.

```fish
set sock "$HOME/Library/Application Support/Timi/claude-hooks.sock"

# Un petit Timi « timi » passe en urgent
curl -s -m 1 --unix-socket "$sock" -H "X-Timi-Pid: $fish_pid" --data-binary '{"hook_event_name":"PermissionRequest","session_id":"test-timi","cwd":"'$PWD'"}' http://timi/claude-hook

# Il passe en « a fini, à toi » (doux)
curl -s -m 1 --unix-socket "$sock" -H "X-Timi-Pid: $fish_pid" --data-binary '{"hook_event_name":"Stop","session_id":"test-timi","cwd":"'$PWD'"}' http://timi/claude-hook

# Il disparaît
curl -s -m 1 --unix-socket "$sock" -H "X-Timi-Pid: $fish_pid" --data-binary '{"hook_event_name":"SessionEnd","session_id":"test-timi","cwd":"'$PWD'"}' http://timi/claude-hook
```

Pour tester les jauges, envoie un JSON de statusline avec des limites (`resets_at` dans 2 h pour la fenêtre de 5 h, dans 3 jours pour la semaine). Il faut au moins un petit Timi à l'écran (commandes ci-dessus). Timi répond 204.

```fish
set sock "$HOME/Library/Application Support/Timi/claude-hooks.sock"
set reset5 (math (date +%s) + 7200)
set reset7 (math (date +%s) + 259200)

curl -s -m 1 --unix-socket "$sock" --data-binary '{"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":'$reset5'},"seven_day":{"used_percentage":78,"resets_at":'$reset7'}}}' http://timi/claude-statusline
```

Une fausse lecture reste prioritaire tant que sa fenêtre n’est pas terminée : une vraie fenêtre qui se réinitialise plus tôt serait ignorée. Après le test, efface-la puis relance Timi :

```fish
pkill -x Timi; defaults delete io.github.chris2cant.Timi claudeUsageLimits; open /Applications/Timi.app
```

## Visibilité

Les petits Timi se masquent avec le grand Timi (menu Afficher/Masquer) et lorsque le réglage « Sessions Claude Code » est désactivé dans Réglages. En revanche, ils ne se cachent pas avec le masquage automatique du grand Timi : ils doivent pouvoir t'interpeller.

## Limites

- Les sessions sont gardées **en mémoire uniquement**. Après un redémarrage de Timi, les sessions ouvertes sont relues depuis `~/.claude/sessions`.
- Une session se termine sur `SessionEnd`, à la mort du process `claude` (vérifiée toutes les 10 s), ou après 5 h sans événement lorsque le PID n'est pas connu.
- Une session « En attente » ou « A fini, à toi » silencieuse depuis plus de 5 h est masquée, même si son process vit encore : Claude Desktop garde un process par conversation ouverte pendant des jours. Elle réapparaît à son prochain événement. Au lancement, l’ancienneté vient du champ `statusUpdatedAt` de son fichier. Une session « Travaille » ou « A besoin de toi » reste affichée tant que son process vit.
- L'app **n'est pas sandboxée** : le socket dans `~/Library/Application Support` et le lancement des CLI herdr et cmux en dépendent. Si la sandbox est un jour activée, ces deux points seront à revoir.
- Sans Timi lancé, les hooks n'ont aucun effet visible : Claude n'est pas bloqué, mais rien ne s'affiche.
- Si `settings.json` est synchronisé sur une autre machine sans Timi, la statusline y échoue silencieusement : le script Timi n'existe pas là-bas, donc ta statusline d'origine n'est pas lancée non plus. Dans ce cas, garde un `settings.json` propre à chaque machine, ou lance `claude-hooks.sh uninstall` avant la synchronisation.
- Les limites n'existent que pour les comptes Pro et Max, et seulement après la première réponse de l'API : sans lecture, la jauge reste masquée.
