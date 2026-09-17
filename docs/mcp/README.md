# LifeOS ↔ MCP — Vision et roadmap

## Qu'est-ce que MCP ?

**MCP** (Model Context Protocol) est un standard ouvert publié par Anthropic
en novembre 2024. Il définit comment un LLM (Claude, GPT, autre) se branche
sur des sources de données ou des tools externes, de façon uniforme.

- Un **serveur MCP** expose des **resources** (données lisibles) et des
  **tools** (actions exécutables).
- Un **client MCP** (Claude Desktop, Cursor, Zed, futurs autres) se
  connecte à ces serveurs et enrichit ses conversations.

Le protocole passe par JSON-RPC 2.0 sur stdio (local) ou WebSocket (distant).

## Pourquoi c'est stratégique pour LifeOS

LifeOS collecte des données de vie riches et structurées (habitudes,
sommeil, objectifs, humeur). Ces données restent aujourd'hui dans le
téléphone de l'utilisateur — inaccessibles à ses autres outils IA.

En devenant un **serveur MCP**, LifeOS permet à l'user de dire à Claude
Desktop, Cursor ou n'importe quel client MCP compatible :

> "Regarde mes habitudes de la semaine et propose-moi un ajustement."
>
> "Compare mes objectifs actifs et priorise-les."
>
> "Écris un article de blog basé sur ce que j'ai fait ce mois-ci."

Tout ça **sans que l'user ait à copier-coller ses données**.

À l'inverse, LifeOS peut être **client MCP** et brancher son coach interne
sur des serveurs externes : le calendrier de l'user, ses mails, ses
documents, son code. Le coach devient alors capable de suggérer :

> "Tu as un RDV client à 14h et tu n'as pas déjeuné — voici un plan pour
> tenir jusque là."

## Statut actuel — Loop 27

**Ce qui existe** (`LifeOS/Services/AICore/MCPBridge.swift`) :

- Protocol `MCPServerBridge` — contrat des futures implémentations
- Types de données : `MCPResource`, `MCPTool`, `MCPConsent`, `MCPDataCategory`
- Bridge par défaut `DefaultLifeOSMCPBridge` qui expose la liste des
  resources/tools qui **seront** disponibles à terme (documentation vivante)
- Aucune implémentation fonctionnelle (JSON-RPC, WebSocket, auth) — c'est
  volontaire, ce round pose juste les fondations conceptuelles

**Ce qui manque** :

- Serveur JSON-RPC 2.0 réel (WebSocket sur localhost + éventuellement
  bonjour pour discovery LAN)
- Client MCP pour brancher des serveurs externes
- Système d'auth (OAuth device flow ou token statique)
- UI de consentement resource par resource
- Log dans `AIActivityLogger` de chaque requête entrante

## Roadmap

### Phase 1 — Fondations (fait, Loop 27)

- Protocol + doc + roadmap
- Aucune surface exposée réellement

### Phase 2 — Serveur MCP read-only localhost

- Serveur JSON-RPC 2.0 sur `ws://localhost:5433/lifeos`
- Expose 4 resources read-only : habitudes 7j, objectifs actifs,
  sommeil 7j, historique coach 30j
- Test avec Claude Desktop (fichier `~/.config/claude-desktop/mcp_servers.json`)
- Aucune écriture, aucune auth (localhost = confiance implicite)

### Phase 3 — Auth + consentement par resource

- Token statique généré par LifeOS et affiché à l'user pour copier dans
  la config du client
- Écran "Serveurs MCP autorisés" avec révocation possible
- Consentement individuel par resource (`MCPConsent.scope`)

### Phase 4 — Tools écriture

- Exposition des tools `createHabit`, `scheduleReminder`, etc.
- Consentement renforcé pour chaque exécution write
- Log complet dans `AIActivityLogger`
- Rate limit 60 req/min par client MCP

### Phase 5 — Client MCP dans le coach

- Le coach LifeOS peut ajouter des serveurs MCP externes autorisés
- Enrichit les prompts avec du contexte issu de ces serveurs
- Ex: connecte-toi au serveur MCP Google Calendar de l'user

## Sécurité — règles absolues

1. **Aucune donnée user ne sort de LifeOS sans consentement explicite**
   (opt-in par resource, jamais bulk)
2. **Allowlist stricte des tools exposés** — jamais de tool générique
   `writeArbitraryFile` ou `execCommand`
3. **Tokens externes stockés dans le Keychain** via
   `AIProviderCredentials` étendu (nouveaux slots à créer en phase 3)
4. **Log toutes les requêtes** entrantes/sortantes dans `AIActivityLogger`
5. **Rate limit local** (60 req/min par client MCP autorisé)
6. **Révocation instantanée** possible depuis un écran dédié dans les
   réglages du coach
7. **Aucun log de contenu** — juste métadonnées (client, resource, timestamp)
   sauf activation `#if DEBUG`

## Références

- Spec MCP officielle : https://spec.modelcontextprotocol.io/
- Serveurs MCP existants : https://github.com/modelcontextprotocol/servers
- SDK Swift MCP : https://github.com/modelcontextprotocol/swift-sdk
  (à évaluer en phase 2 pour ne pas réinventer)

## Décisions techniques figées

- **Transport** : WebSocket local (`ws://localhost:5433`) pour simplicité
  et compatibilité Claude Desktop. Pas de HTTP (pas de streaming natif).
- **Auth** : token statique en phase 3, OAuth device flow en phase 5 si
  besoin de serveurs distants.
- **Storage consentements** : SwiftData (`@Model MCPConsent`) pour
  faciliter les requêtes et la révocation.
- **Format** : JSON-RPC 2.0 strict (rejeter tout ce qui ne respecte pas
  la spec).
- **Naming resources** : URI stable `lifeos://<domain>/<query>` — jamais
  d'ID mutable.

## Contact / questions

Modifier ce document via PR — toute évolution de la vision MCP doit être
tracée ici avant modification du code.
