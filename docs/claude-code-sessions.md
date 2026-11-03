# Sessions Claude Code

Timi peut afficher **un petit Timi par session Claude Code en cours**. Chaque petit Timi reflète le statut de sa session : il **t'interpelle** quand la session a besoin de toi, et un clic fait passer le focus sur son terminal (pane herdr, workspace cmux, ou l’app qui l’héberge : Terminal, iTerm2, Ghostty, VS Code…).

Le grand Timi ne change pas. Les petits Timi se rangent à côté de lui et le suivent : en ligne horizontale quand il est collé en bas ou en haut (coins compris) ou flottant, en colonne verticale quand il est collé au bord gauche ou droit. Comme le grand Timi, ceux de la première ligne se collent au même bord de l’écran avec les mêmes raccords ; leur nom, leur bulle et leur saut passent du côté intérieur.

## Fonctionnement

1. Claude Code exécute la commande d'un hook à chaque événement configuré.
2. Cette commande envoie le JSON de l'événement avec `curl` vers le socket Unix `~/Library/Application Support/Timi/claude-hooks.sock`.
3. Timi met à jour l'état de la session, identifiée par son `session_id`, puis met à jour les petits Timi.

La communication est **locale uniquement** : il s'agit d'un socket Unix, pas d'un port TCP. Rien n'écoute sur le réseau, il n'y a pas de conflit de port ni de demande du pare-feu, et seul ton utilisateur macOS peut se connecter au socket (`~/Library` est en 0700).

Si Timi est fermé, la connexion est refusée immédiatement. La commande sort alors avec le code 0 grâce à `|| true`, et `-m 1` limite l'attente à une seconde. Claude n'est donc jamais bloqué par Timi. Côté Claude Code, chaque hook a en plus un `timeout` de 5 secondes.

Le nom affiché sous chaque petit Timi est celui du projet : on remonte depuis le dossier de travail jusqu'au dossier contenant `.git`, sinon on prend le nom du dossier courant. L'infobulle indique le projet et le statut en clair.

## Installation

`./scripts/install.sh` installe Timi **et** les hooks. Pour ne gérer que les hooks :

```sh
./scripts/claude-hooks.sh install    # ajoute ou met à jour l’entrée Timi des onze événements
./scripts/claude-hooks.sh status     # code de sortie 0 si les onze sont à jour
./scripts/claude-hooks.sh uninstall  # retire uniquement les entrées Timi
```

Le script modifie `~/.claude/settings.json` (ou `$CLAUDE_CONFIG_DIR/settings.json`), hors du repo, avec le `jq` fourni par macOS. Il crée le fichier s’il n’existe pas, refuse un JSON invalide, conserve les autres hooks, ne duplique jamais l’entrée Timi et écrit une sauvegarde `settings.json.bak-timi` avant toute modification. En cas de problème : `mv ~/.claude/settings.json.bak-timi ~/.claude/settings.json`.

Les sessions Claude Code déjà ouvertes doivent être relancées pour charger les nouveaux hooks.

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
| Travaille | Regard qui balaie, respiration rapide, liseré et halo bleus | `UserPromptSubmit`, `PreToolUse` (hors questions), `PostToolUse`, `PostToolUseFailure`, `SubagentStart` |
| A besoin de toi (urgent) | Saut toutes les 1,5 s, liseré et halo orange, bulle « ! » | `PermissionRequest` ; `PreToolUse` pour `AskUserQuestion` et `ExitPlanMode` ; `Notification` de type `permission_prompt` ou `elicitation_dialog` |
| A fini, à toi (doux) | Frétillement à l'entrée, puis pulsation d'un point vert | `Stop` ; `Notification` de type `idle_prompt` |
| En attente | Moitié de sa taille, collé à son bord, yeux mi-clos, immobile | `SessionStart` (un `SessionStart` après compactage ne change pas le statut) |

Règles complémentaires :

- Une session est supprimée à l'événement `SessionEnd`.
- Une session inconnue est créée au premier événement reçu.
- Au lancement, Timi lit les fichiers `~/.claude/sessions/<pid>.json` que Claude Code tient pour chaque session ouverte. Les sessions dont le process est vivant apparaissent tout de suite : « Travaille » si le fichier indique `busy`, « En attente » sinon. Ce format n’est pas documenté par Claude Code : un fichier illisible est ignoré, et la session apparaît alors à son prochain événement. Une session bloquée sur une demande n’est reconnue comme urgente qu’à son prochain événement, et le clic ne peut focus son terminal qu’après ce premier événement.
- `SubagentStop` ne change pas le statut : Claude Code termine des agents internes juste après `Stop`, et le tour doit rester fini.
- Un événement d'un sous-agent ne fait jamais repasser une session « A besoin de toi » à « Travaille ». Seul le fil principal lève l'alerte.
- Les autres types de `Notification` sont ignorés.

## Clic

Un clic sur un petit Timi focus le terminal de la session :

- **Claude Desktop** : si le fichier `~/.claude/sessions/<pid>.json` de la session indique `"entrypoint": "claude-desktop"`, Timi ouvre `claude://code/continue?session=<hostSessionId>`. Claude Desktop passe alors au premier plan sur cette conversation. Ce lien n’est pas documenté : c’est celui qu’utilise le menu du Dock de Claude Desktop (« Continue Last Claude Code Session »). S’il change, le clic n’aura plus d’effet sur ces sessions.
- **herdr** : si la session tourne dans un pane herdr, Timi lance `herdr agent focus <pane>` avec le pane et le socket transmis par le hook. herdr bascule alors sur le workspace, l’onglet et le pane de l’agent.
- **cmux** : Timi lance la CLI cmux (`select-workspace`) avec le workspace et le socket transmis par le hook, puis active cmux. Quand herdr tourne dans cmux, les variables cmux sont héritées et cette étape amène au premier plan le workspace cmux qui héberge herdr.
- **Autres terminaux et éditeurs** (Terminal, iTerm2, Ghostty, Warp, VS Code, Cursor…) : Timi remonte l’arbre des processus depuis le PID de `claude` (`sysctl`, sans permission) jusqu’à la première app macOS ordinaire, et la passe au premier plan. Seule l’app est activée : choisir sa fenêtre ou son onglet demanderait des Apple Events et une permission d’automatisation.

Un herdr lancé dans un autre terminal que cmux reçoit le focus du pane, puis ce terminal est activé de la même façon, tant que le serveur herdr reste un descendant du terminal qui l’a lancé.

Si aucune app n’est trouvée dans l’arbre (session dans tmux, dont le serveur est détaché du terminal, ou serveur herdr rattaché depuis un autre terminal), Timi active cmux s’il est ouvert, sinon rien.

Le focus passe par un processus lancé directement, sans Apple Events : aucune permission d'automatisation n'est demandée.

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

## Visibilité

Les petits Timi se masquent avec le grand Timi (menu Afficher/Masquer) et lorsque le réglage « Sessions Claude Code » est désactivé dans Réglages. En revanche, ils ne se cachent pas avec le masquage automatique du grand Timi : ils doivent pouvoir t'interpeller.

## Limites

- Les sessions sont gardées **en mémoire uniquement**. Après un redémarrage de Timi, les sessions ouvertes sont relues depuis `~/.claude/sessions`.
- Une session se termine sur `SessionEnd`, à la mort du process `claude` (vérifiée toutes les 10 s), ou après 5 h sans événement lorsque le PID n'est pas connu.
- Une session « En attente » ou « A fini, à toi » silencieuse depuis plus de 5 h est masquée, même si son process vit encore : Claude Desktop garde un process par conversation ouverte pendant des jours. Elle réapparaît à son prochain événement. Au lancement, l’ancienneté vient du champ `statusUpdatedAt` de son fichier. Une session « Travaille » ou « A besoin de toi » reste affichée tant que son process vit.
- L'app **n'est pas sandboxée** : le socket dans `~/Library/Application Support` et le lancement des CLI herdr et cmux en dépendent. Si la sandbox est un jour activée, ces deux points seront à revoir.
- Sans Timi lancé, les hooks n'ont aucun effet visible : Claude n'est pas bloqué, mais rien ne s'affiche.
