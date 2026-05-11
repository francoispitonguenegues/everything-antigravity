# Guide du développement agentique dans Google Antigravity

> Guide pratique à destination des développeurs juniors.
> Ce document explique ce qu'est le développement agentique, comment exploiter
> le cadre fourni dans le dossier `.agents/`, et illustre le tout par un exemple
> concret : la création d'une application Symfony de synthèse d'actualité IA
> à partir de flux RSS.

---

## Table des matières

1. [Qu'est-ce que le développement agentique ?](#1--quest-ce-que-le-développement-agentique-)
2. [Mettre en œuvre le cadre agentique dans Antigravity](#2--mettre-en-œuvre-le-cadre-agentique-dans-antigravity)
3. [Exemple Symfony : synthèse d'actualités IA](#3--exemple-pas-à-pas--application-symfony-de-synthèse-ia)
4. [Exemple Spring Boot : base de connaissance Markdown](#4--exemple-pas-à-pas--application-spring-boot-de-base-de-connaissance)

---

# 1 — Qu'est-ce que le développement agentique ?

## 1.1 Le concept en une phrase

Le développement agentique, c'est **programmer avec un assistant IA qui ne se
contente pas de compléter du code** : il comprend votre projet, applique des
règles de qualité, orchestre des vérifications, et peut même coordonner
plusieurs spécialistes pour résoudre un problème.

## 1.2 La différence avec l'autocomplétion classique

| | Autocomplétion classique | Développement agentique |
|---|---|---|
| **Portée** | Complète la ligne en cours | Comprend l'architecture du projet |
| **Contexte** | Le fichier ouvert | L'ensemble du codebase + les règles |
| **Initiative** | Attend votre saisie | Propose, vérifie, corrige proactivement |
| **Qualité** | Aucune vérification | Applique des règles de sécurité et de qualité |
| **Collaboration** | Un seul modèle | Plusieurs « agents » spécialisés |

## 1.3 Les concepts clés

### Skills (compétences)

Un **skill** est un ensemble d'instructions spécialisées que l'agent peut
mobiliser. Par exemple :

- `python-patterns` : connaît les idiomes Python, PEP 8, les type hints
- `security-review` : sait auditer la sécurité d'un endpoint API
- `tdd-workflow` : applique le cycle test-first (écrire le test, puis le code)
- `laravel-patterns` : connaît les conventions de Laravel/Symfony/PHP

Votre dossier `.agents/skills/` en contient plus de 230. L'agent les consulte
**automatiquement** en fonction du contexte de votre question.

### Workflows (commandes)

Un **workflow** est une procédure pas à pas que vous déclenchez explicitement.
Ils se trouvent dans `.agents/workflows/`. Exemples :

- `/code-review` : lance une revue de code structurée
- `/plan` : crée un plan d'implémentation avant de coder
- `/build-fix` : détecte et corrige les erreurs de build
- `/test-coverage` : analyse la couverture de tests

### Rules (règles)

Les **règles** dans `.agents/rules/` sont des garde-fous permanents :

- `gateguard.md` : oblige l'agent à vérifier les faits avant d'écrire du code
- `bash-safety.md` : empêche l'exécution de commandes dangereuses (`rm -rf /`)
- `config-protection.md` : protège les fichiers sensibles (`.env`, clés SSH)
- `quality-gate.md` : vérifie la qualité après chaque modification

Ces règles s'appliquent **en permanence**, sans que vous ayez à y penser.

### Hooks (événements du cycle de vie)

Les **hooks** dans `.agents/rules/hooks/` se déclenchent à des moments précis :

```
bash-safety         → vérifie la sécurité des commandes Bash
config-protection   → protège les fichiers de configuration sensibles
design-quality      → contrôle qualité du frontend avant affichage
gateguard           → force la recherche de faits avant toute modification
quality-gate        → contrôle qualité après modification d'un fichier
session-context     → charge le contexte du projet au démarrage
strategic-compaction → optimise la fenêtre de contexte en cours de session
```

### Pipelines (orchestration multi-agents)

Les **pipelines** dans `.agents/pipelines/` coordonnent plusieurs agents :

```
code-review :  reviewer  →  fixer  →  verifier
gan-loop    :  generator ↔ evaluator (boucle d'amélioration)
tdd-cycle   :  test-writer → implementer → verifier
```

C'est comme avoir une équipe de développeurs spécialisés qui collaborent.

### Graphe de dépendances

Le fichier `skill-graph.json` cartographie les relations entre skills :

- **`depends_on`** : le skill A a besoin du skill B
- **`enhances`** : le skill A améliore le skill B
- **`related_to`** : les skills sont thématiquement liés

L'agent utilise ce graphe pour charger automatiquement les skills pertinents.

### Identité agent (`system.md`)

Le fichier `system.md` est le **cerveau** de l'agent. Il contient :

- Son identité et son rôle
- Le catalogue complet des skills disponibles
- Les règles de sécurité actives
- Les pipelines d'orchestration

C'est la première chose que l'agent lit au démarrage de chaque session.

## 1.4 Pourquoi c'est utile pour un junior ?

1. **Filet de sécurité** : les règles empêchent les erreurs classiques
   (supprimer un fichier de prod, committer un mot de passe, etc.)
2. **Montée en compétences** : les skills contiennent les meilleures pratiques
   de chaque technologie — l'agent vous les applique en temps réel
3. **Revue de code permanente** : au lieu d'attendre la review d'un senior,
   l'agent vérifie la qualité immédiatement
4. **Gain de temps** : les workflows automatisent les tâches répétitives
   (setup de projet, tests, déploiement)

---

# 2 — Mettre en œuvre le cadre agentique dans Antigravity

## 2.1 Prérequis

Avant de commencer, assurez-vous d'avoir :

- [ ] **Google Antigravity** installé et fonctionnel
- [ ] **Le dossier `.agents/`** à la racine de votre projet (généré par le
      script `everything-antigravity.sh`)
- [ ] `python3` installé (pour les outils de maintenance)

## 2.2 Vérifier l'installation

Ouvrez un terminal dans votre projet et lancez :

```bash
# Vérifier que le dossier .agents/ existe
ls .agents/

# Résultat attendu :
# ea-install-state.json  pipelines/  rules/  scripts/
# security-report.json    skill-graph.json  skills/  system.md  workflows/
```

Si le dossier n'existe pas, exécutez l'installation :

```bash
bash everything-antigravity.sh ./everything-claude-code
```

## 2.3 Comprendre la structure

```
votre-projet/
├── .agents/                        ← Le cadre agentique
│   ├── system.md                  ← Identité de l'agent (ne pas modifier)
│   ├── skills/                    ← 234 compétences spécialisées
│   ├── workflows/                 ← 68 procédures invocables
│   ├── rules/                     ← 87 règles permanentes
│   │   └── hooks/                 ← 7 déclencheurs automatiques
│   ├── pipelines/                 ← 6 orchestrations multi-agents
│   ├── scripts/                   ← 5 outils de maintenance
│   ├── skill-graph.json           ← Carte des relations entre skills
│   └── security-report.json       ← Dernier audit de sécurité
├── src/                           ← Votre code applicatif
├── tests/                         ← Vos tests
└── ...
```

> **Règle d'or** : ne modifiez jamais manuellement les fichiers dans `.agents/`.
> Utilisez le script `everything-antigravity.sh` pour les mises à jour.

## 2.4 Ouvrir le projet dans Antigravity

1. Lancez Google Antigravity
2. Ouvrez le dossier de votre projet (`File → Open Folder`)
3. L'agent détecte automatiquement le dossier `.agents/` et charge :
   - L'identité depuis `system.md`
   - Les skills pertinents depuis `skills/`
   - Les règles depuis `rules/`

## 2.5 Interagir avec l'agent

### Poser une question

Ouvrez le panneau de chat de l'agent et posez votre question en langage
naturel :

```
Comment créer un contrôleur Symfony pour afficher une liste d'articles ?
```

L'agent va :
1. Détecter que vous travaillez avec Symfony (grâce au skill `laravel-patterns`
   et aux fichiers de votre projet)
2. Consulter les règles de qualité (`quality-gate.md`)
3. Proposer du code conforme aux conventions Symfony
4. Vérifier la sécurité (pas d'injection SQL, pas de XSS)

### Utiliser un workflow

Tapez une commande slash dans le chat :

```
/plan Créer un système d'import RSS avec parsing et stockage en base
```

L'agent va :
1. Analyser votre codebase existant
2. Identifier les patterns et conventions en place
3. Produire un plan d'implémentation détaillé
4. **Attendre votre validation** avant de toucher au code

### Laisser les règles agir

Vous n'avez rien à faire — les règles s'appliquent automatiquement :

- Si vous demandez d'exécuter `rm -rf /`, le hook `bash-safety` bloque
- Si l'agent veut modifier `.env`, le hook `config-protection` demande
  confirmation
- Après chaque modification de fichier, `quality-gate` vérifie le résultat

## 2.6 Les outils de maintenance

Cinq scripts utilitaires sont disponibles dans `.agents/scripts/` :

```bash
# Diagnostic complet de l'installation
.agents/scripts/ea-doctor

# Lister tous les skills installés
.agents/scripts/ea-list skills

# Voir le tableau de bord
.agents/scripts/ea-status

# Rechercher un skill par mot-clé
.agents/scripts/ea-catalog symfony

# Désinstaller proprement
.agents/scripts/ea-uninstall
```

## 2.7 Mettre à jour le cadre

Quand une nouvelle version d'EA est disponible :

```bash
cd everything-claude-code && git pull && cd ..
bash everything-antigravity.sh ./everything-claude-code --update --project ./votre-projet
```

La mise à jour est **incrémentale** : seuls les fichiers modifiés sont copiés.
Le flag `--project` garantit que la mise à jour cible bien le bon `.agents/`.

---

## 2.8 — Observer le fonctionnement de l'agent grâce aux logs

Le cadre agentique intègre un mécanisme de **logging** qui trace les appels aux
skills, workflows, rules, hooks et pipelines.

C'est un outil pédagogique essentiel : il vous permet de voir ce que l'agent
fait « sous le capot ».

### Les 2 niveaux de log

| Niveau | Comportement | Usage recommandé |
|---|---|---|
| `silent` | Aucune trace | Production, travail normal |
| `info` | Une ligne par appel (heure, type, ressource) | Formation, exploration |

### Changer le niveau de log

```bash
.agents/scripts/ea-logger level info     # activer le logging
.agents/scripts/ea-logger level silent   # désactiver
.agents/scripts/ea-logger level          # voir le niveau actuel
```

### Lire les logs en temps réel

Ouvrez un second terminal dans votre projet et lancez :

```bash
.agents/scripts/ea-logger tail
```

Chaque appel à une ressource s'affichera en temps réel pendant que vous
interagissez avec l'agent dans Antigravity.

### Consulter les logs après coup

```bash
.agents/scripts/ea-logger view 50    # 50 dernières entrées
.agents/scripts/ea-logger stats      # statistiques du jour
.agents/scripts/ea-logger clear      # archiver et vider
```

### Lire une ligne de log

```
14:32:07 | SKILL | python-patterns
14:32:19 | WORKFLOW | /plan
14:33:01 | HOOK | quality-gate
──────── | ──── | ─────────────
Heure      Type   Ressource
```

| Champ | Signification |
|---|---|
| `HH:MM:SS` | Heure exacte de l'appel |
| `TYPE` | `SKILL`, `WORKFLOW`, `RULE`, `HOOK` |
| Nom ressource | La ressource invoquée (`python-patterns`, `/plan`, etc.) |

> **Astuce** : la durée réelle entre deux appels se calcule par la différence
> des timestamps de deux lignes consécutives.

### Où sont stockés les fichiers de log ?

```
.agents/
└── logs/                          ← créé automatiquement au premier appel
    ├── agent-2026-05-09.log       ← log du jour (un fichier par date)
    └── agent-2026-05-08.log       ← logs des jours précédents
```

> **Note pour les juniors** : ces logs tracent ce que l'agent *déclare* faire.
> C'est un outil de formation, pas un audit de production. Pour la télémétrie
> exacte (tokens, coûts), consultez le tableau de bord Antigravity.

---

## 2.9 — Discipliner l'agent avec un prompt de début de session

En pratique, l'agent peut « oublier » d'appeler le logger ou l'appeler avec
des valeurs génériques (`response antigravity`) au lieu des vrais noms de
ressources. Pour éviter ce problème, **collez ce prompt au début de chaque
session de travail** :

### Prompt de calibration (à copier-coller)

```
Avant de commencer, lis et applique strictement la règle `.agents/rules/agent-logging.md`.

Rappel : à CHAQUE réponse, ta PREMIÈRE action doit être d'exécuter :
.agents/scripts/ea-logger log <type> <name> || true

Règles :
- <type> = skill | workflow | rule | hook | pipeline (JAMAIS "response")
- <name> = identifiant réel de la ressource (JAMAIS "antigravity" ou "unknown")
- Si j'invoque /plan → ea-logger log workflow /plan
- Si tu appliques jpa-patterns → ea-logger log skill jpa-patterns
- Si aucun skill/workflow précis → ea-logger log rule <nom-de-la-règle>
- Si plusieurs ressources dans une réponse → un appel par ressource

Confirme que tu as compris en exécutant :
.agents/scripts/ea-logger log rule agent-logging || true
```

### Pourquoi ça fonctionne

Ce prompt exploite trois mécanismes complémentaires :

1. **Référence au fichier de règle** — l'agent le lit et intègre les
   instructions complètes, y compris les exemples et la table de décision
2. **Exemples concrets ✅/❌** — réduit l'ambiguïté pour n'importe quel modèle
3. **Action de vérification** — l'agent doit *prouver* sa compréhension en
   exécutant la commande, ce qui valide immédiatement que le script fonctionne

### Garde-fous automatiques

Même sans ce prompt, le script `ea-logger` rejette automatiquement les appels
invalides grâce à deux validations :

- **Type invalide** → `⚠️ ea-logger: invalid type 'response'. Must be one of:
  skill workflow rule hook pipeline`
- **Nom générique** → `⚠️ ea-logger: invalid name 'antigravity'. Use the actual
  resource identifier.`

Ces validations sont définies dans `.agents/scripts/ea-logger` (fonction
`cmd_log`). Si l'appel échoue, le `|| true` empêche de bloquer la réponse
de l'agent — mais l'erreur est visible dans le terminal.

### Vérifier que le logger fonctionne

Après avoir collé le prompt de calibration, vérifiez dans un second terminal :

```bash
.agents/scripts/ea-logger tail
```

Vous devriez voir apparaître la première ligne :

```
[HH:MM:SS] [RULE    ] agent-logging
```

Si elle apparaît, l'agent est correctement calibré pour la session.

---

# 3 — Exemple pas à pas : application Symfony de synthèse IA


Nous allons créer une application web complète qui :

- Collecte des flux RSS depuis des sites de référence sur l'IA
- Parse et stocke les articles en base de données
- Affiche une synthèse quotidienne des actualités IA
- Propose un résumé intelligent de chaque article

## Étape 0 — Créer le projet

### 0.1 Initialiser le projet Symfony

Ouvrez Antigravity et demandez à l'agent :

```
Crée un nouveau projet Symfony 7 avec Webapp pack. Le projet s'appelle
"ai-press-review". Utilise PHP 8.3, PostgreSQL, et Twig pour le front.
```

L'agent va exécuter :

```bash
composer create-project symfony/skeleton ai-press-review
cd ai-press-review
composer require webapp
composer require doctrine/orm doctrine/doctrine-bundle
```

### 0.2 Installer le cadre agentique

```bash
# Depuis le dossier parent contenant everything-antigravity.sh
bash everything-antigravity.sh ./everything-claude-code --project ./ai-press-review
```

Le flag `--project` fait deux choses simultanément :
1. **Détecte automatiquement PHP/Symfony** et active les skills pertinents :
   `laravel-patterns`, `php-patterns`, `database-migrations`, `security-review`, `tdd-workflow`
2. **Installe `.agents/` directement dans `./ai-press-review/`** — pas besoin de `cd` dans le projet

### 0.3 Ouvrir dans Antigravity

```
File → Open Folder → ai-press-review/
```

L'agent charge automatiquement le cadre `.agents/` et connaît désormais votre
stack.

## Étape 1 — Modéliser les données

### 1.1 Demander un plan

Dans le chat Antigravity :

```
/plan Créer le modèle de données pour une application de synthèse
d'actualité IA. J'ai besoin de :
- Source RSS (nom, URL du flux, catégorie, actif/inactif)
- Article (titre, lien, contenu, date de publication, date de collecte)
- Résumé (texte résumé, mots-clés, score de pertinence)
Chaque source a plusieurs articles, chaque article a un résumé.
```

L'agent produit un plan détaillé. **Lisez-le et validez** avant de continuer.

### 1.2 Générer les entités

```
Génère les entités Doctrine pour le modèle de données validé.
Utilise les attributs PHP 8 (#[ORM\Entity]), pas les annotations.
Ajoute les validations Symfony (#[Assert\NotBlank], etc.).
```

L'agent génère trois fichiers :

**`src/Entity/Source.php`** :

```php
#[ORM\Entity(repositoryClass: SourceRepository::class)]
class Source
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(length: 255)]
    #[Assert\NotBlank]
    private string $name;

    #[ORM\Column(length: 500)]
    #[Assert\Url]
    private string $url;

    #[ORM\Column(length: 100)]
    private string $category = 'general';

    #[ORM\Column]
    private bool $active = true;

    #[ORM\OneToMany(targetEntity: Article::class, mappedBy: 'source')]
    private Collection $articles;
}
```

**`src/Entity/Article.php`** :

```php
#[ORM\Entity(repositoryClass: ArticleRepository::class)]
class Article
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(length: 255)]
    #[Assert\NotBlank]
    private ?string $title = null;

    #[ORM\Column(type: Types::TEXT, unique: true)]
    #[Assert\Url]
    private ?string $link = null;

    #[ORM\Column(type: Types::TEXT, nullable: true)]
    private ?string $content = null;

    #[ORM\Column(nullable: true)]
    private ?\DateTimeImmutable $publishedAt = null;

    #[ORM\Column]
    private ?\DateTimeImmutable $collectedAt = null;

    #[ORM\ManyToOne(inversedBy: 'articles')]
    #[ORM\JoinColumn(nullable: false)]
    private ?Source $source = null;

    #[ORM\OneToOne(mappedBy: 'article', cascade: ['persist', 'remove'])]
    private ?Summary $summary = null;
}
```

**`src/Entity/Summary.php`** :

```php
#[ORM\Entity(repositoryClass: SummaryRepository::class)]
class Summary
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(type: Types::TEXT)]
    private string $text;

    #[ORM\Column(type: Types::JSON)]
    private array $keywords = [];

    #[ORM\Column(type: Types::FLOAT)]
    private float $relevanceScore = 0.0;

    #[ORM\OneToOne(inversedBy: 'summary')]
    #[ORM\JoinColumn(nullable: false)]
    private Article $article;
}
```

### 1.3 Générer la migration

```
Génère la migration Doctrine pour ces entités.
```

```bash
php bin/console make:migration
php bin/console doctrine:migrations:migrate
```

> **Note** : le hook `quality-gate` vérifie automatiquement que les entités
> respectent les conventions Doctrine (nommage, types, relations).

## Étape 2 — Créer le service de collecte RSS

### 2.1 Demander l'implémentation

```
Crée un service RssCollector qui :
1. Lit toutes les sources RSS actives depuis la base
2. Pour chaque source, parse le flux RSS avec SimplePie ou FeedIo
3. Pour chaque article non encore en base (vérification par URL),
   crée une entité Article et la persiste
4. Retourne le nombre d'articles importés

Utilise l'injection de dépendances Symfony.
Ajoute une commande console `app:rss:collect` pour lancer la collecte.
```

L'agent génère :

**`src/Service/RssCollector.php`** — le service de collecte :

```php
class RssCollector
{
    public function __construct(
        private readonly SourceRepository $sourceRepo,
        private readonly ArticleRepository $articleRepo,
        private readonly EntityManagerInterface $em,
        private readonly LoggerInterface $logger,
        private readonly ValidatorInterface $validator,
    ) {}

    public function collect(): int
    {
        $imported = 0;
        $sources = $this->sourceRepo->findBy(['active' => true]);

        foreach ($sources as $source) {
            // parsing RSS, déduplication par URL, validation, persistance
        }

        $this->em->flush();
        return $imported;
    }
}
```

**`src/Command/RssCollectCommand.php`** — la commande console :

```php
#[AsCommand(name: 'app:rss:collect', description: 'Collecte les articles depuis les flux RSS')]
class RssCollectCommand extends Command
{
    public function __construct(private readonly RssCollector $collector)
    {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);
        $count = $this->collector->collect();
        $io->success(sprintf('%d nouvel(s) article(s) importé(s) avec succès !', $count));
        return Command::SUCCESS;
    }
}
```

### 2.2 Demander des tests

```
/test-coverage Écris les tests unitaires pour RssCollector.
Mock le repository et le EntityManager. Teste :
- collectAll() avec 0 sources
- collectAll() avec 2 sources actives
- la déduplication (un article déjà en base n'est pas réimporté)
```

L'agent applique le workflow TDD et génère les tests PHPUnit.

## Étape 3 — Créer les contrôleurs et les vues

### 3.1 Page d'accueil — synthèse du jour

```
Crée un contrôleur DashboardController avec une action index() qui :
1. Récupère les articles du jour, triés par date de publication DESC
2. Les groupe par source
3. Les passe à un template Twig "dashboard/index.html.twig"

Le template doit afficher :
- Un header avec le titre "Synthèse IA du jour" et la date
- Pour chaque source, une carte avec le nom et le nombre d'articles
- Pour chaque article, le titre (cliquable), la date, et le résumé
  s'il existe

Utilise un design moderne et responsive avec du CSS vanilla.
```

### 3.2 Page de gestion des sources

```
Crée un CRUD complet pour l'entité RssSource :
- Liste des sources avec statut actif/inactif
- Formulaire d'ajout/édition (nom, URL du flux, catégorie)
- Action toggle actif/inactif
- Action de suppression avec confirmation

Ajoute un lien de navigation entre le dashboard et la gestion des sources.
```

### 3.3 Vérifier la sécurité

```
/code-review Fais une revue de sécurité des contrôleurs et des templates.
Vérifie : CSRF, XSS, injection SQL, validation des entrées.
```

L'agent utilise le pipeline `code-review` qui enchaîne :

1. **Reviewer** : identifie les problèmes potentiels
2. **Fixer** : propose des corrections
3. **Verifier** : confirme que les corrections sont valides

## Étape 4 — Ajouter les sources RSS

### 4.1 Fixtures de données

```
Crée des fixtures Doctrine avec 5 sources RSS réelles sur l'IA :
- The Verge (catégorie : tech)
- MIT Technology Review (catégorie : research)
- VentureBeat AI (catégorie : business)
- Ars Technica AI (catégorie : tech)
- AI News (catégorie : general)

Utilise les vraies URLs de flux RSS de ces sites.
```

### 4.2 Charger les fixtures

```bash
php bin/console doctrine:fixtures:load
```

### 4.3 Lancer une première collecte

```bash
php bin/console app:rss:collect
# → "42 articles imported."
```

### 4.4 Vérifier le résultat

Ouvrez le navigateur sur `http://localhost:8000` et vérifiez que les articles
s'affichent correctement.

## Étape 5 — Automatiser la collecte

### 5.1 Installer les dépendances

Deux composants sont nécessaires :

```bash
composer require symfony/scheduler
composer require dragonmantank/cron-expression
```

> **Note** : `dragonmantank/cron-expression` est requis par Symfony Scheduler
> dès que l'on utilise `RecurringMessage::cron(...)`. Sans lui, Symfony lèvera
> une exception à l'exécution.

### 5.2 Configurer le planning

```
Configure le Symfony Scheduler pour lancer la collecte RSS toutes les heures
et la synthèse IA 10 minutes après. Utilise le composant symfony/scheduler
avec des expressions Cron.
```

L'agent génère le `DefaultScheduleProvider` avec deux tâches précises :

```php
#[AsSchedule('default')]
class DefaultScheduleProvider implements ScheduleProviderInterface
{
    public function getSchedule(): Schedule
    {
        return (new Schedule())
            ->add(
                RecurringMessage::cron('0 * * * *', new RssCollectMessage()),       // à h:00
                RecurringMessage::cron('10 * * * *', new ArticlesSummarizeMessage()) // à h:10
            );
    }
}
```

### 5.3 Vérifier

```bash
php bin/console debug:scheduler
# Doit afficher les deux tâches avec leur prochaine exécution
```

### 5.4 Démarrer le worker en arrière-plan

```bash
php bin/console messenger:consume scheduler_default
```

Ce processus doit rester actif (en production, utilisez Supervisor ou un
service systemd) pour que les tâches planifiées s'exécutent automatiquement.

## Étape 6 — Ajouter la synthèse intelligente

### 6.1 Service de résumé

```
Crée un service ArticleSummarizer qui :
1. Prend un Article en entrée
2. Extrait le contenu textuel (strip HTML)
3. Génère un résumé de 2-3 phrases et 5 mots-clés via une API LLM
4. Calcule un score de pertinence (0.0 à 1.0)
5. Crée et persiste une entité Summary

Utilise une interface LlmClientInterface pour découpler l'appel API.
Fournis une implémentation pour OpenAI et un mock pour les tests.
```

### 6.2 Commande de synthèse

```
Crée une commande `app:articles:summarize` qui :
- Récupère les articles sans résumé
- Les passe au service ArticleSummarizer
- Affiche une barre de progression
```

### 6.3 Intégrer dans le scheduler

```
Ajoute la tâche de synthèse au scheduler, 10 minutes après chaque collecte.
```

## Étape 7 — Finaliser et déployer

### 7.1 Revue complète

```
/code-review Fais une revue complète de tout le projet.
Vérifie : architecture, sécurité, performance, tests, documentation.
```

### 7.2 Tests d'intégration

```
Écris des tests d'intégration avec le WebTestCase de Symfony pour :
- GET /dashboard → 200, contient "Synthèse IA"
- GET /sources → 200, liste les sources
- POST /sources/new → crée une source et redirige
- La commande app:rss:collect fonctionne de bout en bout
```

### 7.3 Documentation

```
Génère un README.md pour ce projet avec :
- Description du projet
- Prérequis (PHP 8.3, PostgreSQL, Composer)
- Installation pas à pas
- Configuration des variables d'environnement
- Commandes disponibles
- Contribution
```

## Récapitulatif des interactions avec l'agent

| Étape | Ce que vous demandez | Ce que l'agent fait |
|---|---|---|
| 0 | Créer le projet | `composer create-project` + configuration |
| 1 | Modéliser les données | Génère entités + migration + validation |
| 2 | Service de collecte | Service + commande + injection de dépendances |
| 3 | Contrôleurs + vues | CRUD + templates Twig + CSS |
| 4 | Fixtures | Données réelles + URLs de flux RSS |
| 5 | Automatisation | Symfony Scheduler configuré |
| 6 | Synthèse IA | Service LLM découplé + interface |
| 7 | Finalisation | Revue de code + tests + documentation |

À chaque étape, les **règles** et **hooks** du cadre agentique interviennent
automatiquement :

- `gateguard` vérifie les faits avant d'écrire
- `quality-gate` contrôle la qualité après chaque modification
- `bash-safety` protège contre les commandes dangereuses
- `config-protection` protège `.env` et les fichiers sensibles
- `security-review` analyse les endpoints et les formulaires

## Conseils pour tirer le meilleur du développement agentique

### ✅ À faire

- **Soyez précis** dans vos demandes : « Crée un contrôleur avec injection
  de dépendances et validation CSRF » plutôt que « Fais un contrôleur »
- **Utilisez `/plan` avant de coder** : l'agent analyse votre codebase et
  propose une approche cohérente
- **Lisez les plans avant de valider** : l'agent attend votre accord
- **Demandez des tests** : le workflow `/test-coverage` est votre meilleur ami
- **Faites des revues régulières** : `/code-review` après chaque fonctionnalité

### ❌ À éviter

- **Ne modifiez pas `.agents/`** manuellement — utilisez le script d'install
- **Ne désactivez pas les règles** — elles sont là pour vous protéger
- **Ne faites pas tout en une seule demande** — découpez en étapes
- **Ne validez pas aveuglément** — lisez et comprenez le code généré
- **Ne sautez pas les tests** — ils vous sauveront la vie

### 💡 Astuces avancées

1. **Combinez les workflows** : `/plan` puis `/code-review` puis
   `/test-coverage`
2. **Utilisez `ea-catalog`** pour découvrir des skills que vous ne
   connaissez pas
3. **Le mode `--verbose`** du script d'installation vous montre exactement
   quels skills sont activés pour votre stack
4. **Consultez `skill-graph.json`** pour comprendre les relations entre skills

---

# 4 — Exemple pas à pas : application Spring Boot de base de connaissance

> 🚧 **Travaux en cours**

Ce deuxième exemple approfondit la mise en œuvre du cadre agentique en couvrant
**un maximum de skills, workflows, rules, hooks et pipelines**. Nous construisons
une application web Spring Boot de gestion de documents Markdown personnels.

## L'application « MarkdownVault »

**MarkdownVault** est une base de connaissance personnelle où l'utilisateur peut :

- **Ajouter** des documents Markdown classés par catégorie
- **Supprimer** et **reclasser** les documents existants
- **Visualiser** le rendu HTML de chaque document à la demande
- **Importer** une page web en la convertissant en Markdown via le service
  `curl.md`, avec un titre et une catégorie au choix

## Composants agentiques mobilisés

> Ce tableau récapitule les **43 composants** du cadre agentique que cet exemple
> met en œuvre. Consultez-le au fil des étapes pour comprendre quand et pourquoi
> chaque composant intervient.

### Skills (22)

| Skill | Rôle dans le projet |
|---|---|
| `springboot-patterns` | Architecture du projet, structure des couches |
| `springboot-security` | Authentification, CSRF, validation |
| `springboot-tdd` | Tests unitaires, MockMvc, Testcontainers |
| `springboot-verification` | Boucle de vérification avant merge |
| `java-coding-standards` | Conventions de nommage, immutabilité |
| `jpa-patterns` | Entités, repositories, requêtes optimisées |
| `postgres-patterns` | Schéma, indexation, requêtes performantes |
| `database-migrations` | Flyway, versioning du schéma |
| `api-design` | Endpoints REST, status codes, pagination |
| `hexagonal-architecture` | Ports & Adapters, séparation domaine/infra |
| `security-review` | Audit de sécurité des endpoints |
| `tdd-workflow` | Méthodologie red-green-refactor |
| `docker-patterns` | Conteneurisation, docker-compose |
| `deployment-patterns` | CI/CD, health checks, rollback |
| `git-workflow` | Branches, commits conventionnels, PR |
| `coding-standards` | Lisibilité, conventions transversales |
| `accessibility` | HTML sémantique, ARIA, contraste |
| `seo` | Méta-tags, titres, structure sémantique |
| `architecture-decision-records` | Capture des décisions d'architecture |
| `frontend-patterns` | Patterns Thymeleaf et interface web |
| `design-system` | Cohérence visuelle, composants réutilisables |
| `log-viewer` | Consultation et explication des traces agentiques |

### Workflows (10)

| Workflow | Étape | Rôle |
|---|---|---|
| `/plan` | 1.1 | Plan d'architecture et de données |
| `/feature-dev` | 2.1 | Développement guidé de la fonctionnalité CRUD |
| `/code-review` | 3.3, 5.3, 7.1 | Revue de code à chaque fonctionnalité |
| `/build-fix` | 2.3, 4.2 | Correction automatique des erreurs de build |
| `/test-coverage` | 3.4 | Analyse des lacunes de couverture |
| `/quality-gate` | 5.3 | Contrôle qualité global |
| `/checkpoint` | 3.5, 5.4 | Sauvegarde de l'état d'avancement |
| `/update-docs` | 7.2 | Synchronisation de la documentation |
| `/harness-audit` | 7.3 | Audit du harnais agentique |
| `/gradle-build` | 2.3 | Résolution de build Gradle/Maven |

### Rules (6)

| Rule | Quand elle intervient |
|---|---|
| `agent-logging` | À chaque appel de skill/workflow (logging) |
| `security-baseline` | Vérifie secrets, injections, OWASP |
| `java--coding-style` | Conventions Java à chaque génération de code |
| `quality-gate` | Bloque si seuil de qualité non atteint |
| `common--git-workflow` | Format des messages de commit, stratégie de branches |
| `common--security` | Interdit les clés/mots de passe en dur |

### Hook (1)

| Hook | Rôle |
|---|---|
| `bash-safety` | Sécurise les commandes shell exécutées par l'agent |

### Pipelines (4)

| Pipeline | Étape | Rôle |
|---|---|---|
| `tdd-cycle` | 2.2, 3.2, 4.3 | Boucle test → implémentation → refactor |
| `code-review` | 3.3, 5.3, 7.1 | Revue multi-agents avec convergence |
| `council` | 1.2 | Décision d'architecture à 4 voix |
| `santa-method` | 7.1 | Double revue adverse avant merge final |

---

## Étape 0 — Préparer le projet

### 0.1 Initialiser le projet Spring Boot

```bash
# Via Spring Initializr (CLI)
curl https://start.spring.io/starter.zip \
  -d type=gradle-project \
  -d language=java \
  -d bootVersion=3.5.0 \
  -d baseDir=markdown-vault \
  -d groupId=com.example \
  -d artifactId=markdown-vault \
  -d name=MarkdownVault \
  -d description="Personal Markdown Knowledge Base" \
  -d packageName=com.example.vault \
  -d javaVersion=21 \
  -d dependencies=web,data-jpa,postgresql,flyway,validation,thymeleaf,security,actuator,devtools \
  -o markdown-vault.zip

unzip markdown-vault.zip && rm markdown-vault.zip
cd markdown-vault
git init && git add -A && git commit -m "chore: initial Spring Boot 3.5 scaffold"
```

> ⚠️ *Étape manuelle (terminal) — l'agent n'est pas encore ouvert.*


### 0.2 Installer le cadre agentique

```bash
# Depuis le dossier parent
bash everything-antigravity.sh ./everything-claude-code --project ./markdown-vault
```

Le flag `--project` installe le cadre agentique complet. Les skills pertinents
pour Spring Boot seront disponibles dès l'ouverture dans Antigravity :
`springboot-patterns`, `springboot-security`, `springboot-tdd`, `jpa-patterns`,
`java-coding-standards`, `database-migrations`.

### 0.3 Activer le logging agentique

```bash
# Activer les logs pour observer l'agent (mode formation)
./markdown-vault/.agents/scripts/ea-logger level info

# Ouvrir un second terminal pour voir les appels en temps réel
./markdown-vault/.agents/scripts/ea-logger tail
```

> **Rule configurée** : `agent-logging` — une fois l'agent ouvert, chaque appel sera tracé automatiquement

### 0.4 Ouvrir dans Antigravity

Ouvrez le dossier `markdown-vault/` dans Google Antigravity. L'agent lit
automatiquement `.agents/system.md` et dispose de toutes les compétences Spring Boot.

---

## Étape 1 — Architecture et modèle de données

### 1.1 Demander un plan d'architecture

```
/plan

Conçois l'architecture d'une application Spring Boot "MarkdownVault" :

1. Architecture hexagonale (Ports & Adapters)
2. Modèle de données :
   - Document (id, title, content, category, createdAt, updatedAt)
   - Category (id, name, slug, description, color)
3. API REST pour le CRUD des documents et catégories
4. Service d'import web via curl.md (convertit URL → Markdown)
5. Rendu HTML du Markdown à la demande
6. Authentification par session (Spring Security)

Attends ma validation avant de coder.
```

> **Workflow** : `/plan` — l'agent produit un plan structuré  
> **Skills mobilisés** : `springboot-patterns`, `hexagonal-architecture`,
> `api-design`, `jpa-patterns`, `postgres-patterns`

### 1.2 Valider les choix d'architecture via le conseil

```
/council

Évalue ces 3 options pour le stockage des documents Markdown :
1. Contenu en colonne TEXT PostgreSQL
2. Fichiers .md sur le système de fichiers + métadonnées en BDD
3. Hybride : contenu en BDD pour la recherche, fichier pour le rendu

Contexte : application mono-utilisateur, ~1000 documents max, recherche
plein texte souhaitée à terme.
```

> **Pipeline** : `council` — 4 voix (pragmatique, architecte, sécurité,
> performance) débattent et recommandent. L'utilisateur tranche.

### 1.3 Enregistrer la décision d'architecture

```
Crée un ADR (Architecture Decision Record) pour documenter le choix
de stockage que nous venons de valider. Utilise le format standard
avec contexte, options considérées, et justification.
```

> **Skill** : `architecture-decision-records` — crée `docs/adr/001-storage-strategy.md`

---

## Étape 2 — Couche domaine et persistance

### 2.1 Générer les entités JPA

```
Génère les entités JPA pour Document et Category en suivant :
- Architecture hexagonale : entités dans le package domain
- Annotations JPA modernes (pas de XML)
- Validations Bean Validation (@NotBlank, @Size, etc.)
- Relations bidirectionnelles Document ↔ Category (ManyToOne)
- Audit automatique (createdAt, updatedAt via @EntityListeners)
- Index sur category_id et title pour les recherches
```

L'agent génère le code en respectant les conventions de :

> **Skills mobilisés** : `jpa-patterns`, `java-coding-standards`,
> `hexagonal-architecture`, `coding-standards`  
> **Rule** : `java--coding-style` — l'agent applique les conventions Java automatiquement

**`src/main/java/com/example/vault/domain/Document.java`** :

```java
@Entity
@Table(name = "documents", indexes = {
    @Index(name = "idx_doc_category", columnList = "category_id"),
    @Index(name = "idx_doc_title", columnList = "title")
})
@EntityListeners(AuditingEntityListener.class)
public class Document {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @NotBlank
    @Size(max = 255)
    @Column(nullable = false)
    private String title;

    @NotBlank
    @Column(columnDefinition = "TEXT", nullable = false)
    private String content;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "category_id", nullable = false)
    private Category category;

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate
    @Column(nullable = false)
    private LocalDateTime updatedAt;

    // constructeurs, getters, setters...
}
```

### 2.2 Générer les tests AVANT l'implémentation (TDD)

```
En suivant la méthodologie TDD, écris d'abord les tests pour :
1. DocumentRepository — requêtes personnalisées (findByCategory, searchByTitle)
2. CategoryRepository — contrainte d'unicité du slug
3. Validation des entités — @NotBlank, @Size

Utilise JUnit 5 + Testcontainers PostgreSQL pour les tests d'intégration.
N'implémente pas encore les repositories — écris les tests en premier.
```

> **Pipeline** : `tdd-cycle` — boucle red → green → refactor  
> **Skills** : `springboot-tdd`, `tdd-workflow`  
> **Workflow** : l'agent écrit les tests qui échouent (RED), puis demandera
> de passer à l'étape d'implémentation

### 2.3 Implémenter et corriger le build

```
Implémente les repositories Spring Data JPA pour faire passer les tests.
Ajoute les requêtes dérivées et les @Query personnalisées nécessaires.
```

Si le build échoue :

```
/build-fix
```

> **Workflow** : `/build-fix` — détecte et corrige les erreurs de build  
> **Hook** : `bash-safety` — sécurise les commandes Gradle exécutées

### 2.4 Créer la migration Flyway

```
Génère la migration Flyway V1__create_schema.sql correspondant aux
entités Document et Category. Inclus les index et les contraintes.
Utilise les conventions Flyway (versioning, nommage).
```

> **Skill** : `database-migrations` — migration versionnée et réversible  
> **Skill** : `postgres-patterns` — types de données et indexation optimaux

---

## Étape 3 — Couche service et API REST

### 3.1 Développer le service CRUD

```
/feature-dev

Développe le service DocumentService avec :
1. CRUD complet (create, read, update, delete)
2. Recherche par catégorie, recherche par titre (LIKE insensible à la casse)
3. Pagination et tri (Spring Data Pageable)
4. Conversion Markdown → HTML (via commonmark-java)
5. Validation métier (titre unique par catégorie)

Architecture hexagonale : port (interface) dans domain/, adapter dans infra/.
```

> **Workflow** : `/feature-dev` — développement guidé avec vérifications intégrées  
> **Skills** : `springboot-patterns`, `hexagonal-architecture`, `api-design`

### 3.2 Développer le contrôleur REST (TDD)

```
En TDD, crée le contrôleur REST DocumentController :

1. Tests MockMvc d'abord (GET /api/documents, POST, PUT, DELETE)
2. Tests de pagination (page, size, sort)
3. Tests de validation (400 sur données invalides)
4. Tests de sécurité (401 sans authentification)

Puis implémente le contrôleur pour faire passer les tests.
```

L'agent suit le cycle TDD :

```
Phase RED   → Tests MockMvc qui échouent (contrôleur n'existe pas encore)
Phase GREEN → Implémentation minimale du contrôleur
Phase REFACTOR → Extraction des DTOs, ajout de la pagination
```

> **Pipeline** : `tdd-cycle`  
> **Skills** : `springboot-tdd`, `api-design`

### 3.3 Revue de code multi-agents

```
/code-review

Revue complète de la couche service et API :
- Respect de l'architecture hexagonale
- Sécurité des endpoints
- Conventions de nommage Java
- Optimisation des requêtes JPA (N+1, fetch join)
- Couverture de tests
```

> **Pipeline** : `code-review` — deux agents (reviewer + critic) convergent  
> **Workflow** : `/code-review`  
> **Skills** : `security-review`, `jpa-patterns`, `java-coding-standards`

### 3.4 Analyser la couverture de tests

```
/test-coverage

Analyse la couverture actuelle avec JaCoCo.
Identifie les chemins non testés et génère les tests manquants
pour atteindre 80% de couverture.
```

> **Workflow** : `/test-coverage` — analyse et génération automatique

### 3.5 Checkpoint

```
/checkpoint

Sauvegarde l'état d'avancement : couche domaine + service + API REST
fonctionnels avec 80%+ de couverture de tests.
```

> **Workflow** : `/checkpoint` — point de sauvegarde vérifié

---

## Étape 4 — Service d'import web via curl.md

### 4.1 Concevoir le service d'import

```
Conçois et implémente le service WebImportService qui :

1. Reçoit une URL, un titre et une catégorie de la part de l'utilisateur
2. Appelle l'API curl.md pour convertir la page web en Markdown :
   - Endpoint : https://curl.md/api/convert
   - Méthode : POST { "url": "https://example.com/article" }
   - Réponse : { "markdown": "# Contenu converti..." }
3. Crée un Document avec le Markdown reçu, le titre choisi et la catégorie
4. Gère les erreurs : URL invalide, service indisponible, timeout (5s)

Utilise RestClient (Spring 6.1+) pour l'appel HTTP.
Architecture hexagonale : port WebConverter dans domain/, adapter RestClient
dans infra/.
```

> **Skills** : `springboot-patterns`, `hexagonal-architecture`, `api-design`  
> **Rule** : `security-baseline` — validation de l'URL, pas de SSRF

### 4.2 Sécuriser l'import

```
Audite la sécurité du service WebImportService :
- Validation de l'URL (schéma https uniquement, pas de localhost/IP privée)
- Limitation de la taille du contenu importé (1 Mo max)
- Rate limiting (5 imports par minute par utilisateur)
- Sanitization du Markdown reçu (XSS dans les liens/images)
- Timeout et circuit breaker sur l'appel à curl.md
```

Si le build échoue après les corrections de sécurité :

```
/build-fix
```

> **Skill** : `springboot-security` — patterns de sécurité Spring  
> **Skill** : `security-review` — audit systématique  
> **Rule** : `common--security` — vérifie qu'aucune clé API n'est en dur  
> **Workflow** : `/build-fix`

### 4.3 Tests d'intégration de l'import

```
Écris les tests d'intégration pour WebImportService en TDD :
1. Mock du service curl.md avec WireMock
2. Test du happy path (URL valide → Document créé)
3. Test d'erreur (curl.md indisponible → exception métier)
4. Test de sécurité (URL localhost → rejet avec 400)
5. Test de timeout (réponse > 5s → fallback propre)
6. Test de taille (contenu > 1 Mo → rejet)

Utilise Testcontainers pour PostgreSQL et WireMock pour curl.md.
```

> **Pipeline** : `tdd-cycle`  
> **Skills** : `springboot-tdd`, `tdd-workflow`

---

## Étape 5 — Interface web Thymeleaf

### 5.1 Créer les vues

```
/feature-dev

Crée l'interface web avec Thymeleaf :

1. Layout de base (header, navigation par catégories, footer)
2. Page d'accueil — liste des documents récents avec pagination
3. Page de catégorie — documents filtrés, compteur
4. Page de document — rendu HTML du Markdown + métadonnées
5. Formulaire d'ajout/édition de document (textarea Markdown + preview live)
6. Formulaire d'import web (champ URL + titre + sélection catégorie)
7. Page de gestion des catégories (CRUD)

Design responsive, HTML sémantique, composants accessibles.
```

> **Workflow** : `/feature-dev`  
> **Skills** : `frontend-patterns`, `accessibility`, `seo`, `design-system`

### 5.2 Ajouter l'accessibilité et le SEO

```
Audite et améliore l'accessibilité des vues Thymeleaf :
- Contraste suffisant (WCAG AA)
- Navigation clavier complète
- Attributs ARIA sur les composants interactifs
- Balises meta et structure heading correcte pour le SEO
- Titre <title> dynamique par page
```

> **Skills** : `accessibility`, `seo`

### 5.3 Revue de qualité globale

```
/quality-gate

Vérifie la qualité globale :
- Build Gradle sans erreur ni warning
- Tests unitaires et d'intégration passent
- Couverture ≥ 80%
- Aucune vulnérabilité critique (OWASP dependency-check)
- Conventions de code respectées
```

Puis revue de code :

```
/code-review
```

> **Workflow** : `/quality-gate` puis `/code-review`  
> **Pipeline** : `code-review`  
> **Rule** : `quality-gate` — bloque si seuil non atteint

### 5.4 Checkpoint

```
/checkpoint

Application fonctionnelle complète : CRUD + import web + rendu Markdown
+ interface Thymeleaf accessible. Couverture ≥ 80%.
```

---

## Étape 6 — Conteneurisation et déploiement

### 6.1 Dockeriser l'application

```
Crée la configuration Docker pour MarkdownVault :
1. Dockerfile multi-stage (build Gradle → JRE 21 slim)
2. docker-compose.yml avec :
   - Service app (port 8080)
   - Service PostgreSQL 16 (volume persistant)
3. .dockerignore optimisé
4. Health check via /actuator/health
5. Variables d'environnement pour la configuration
```

> **Skill** : `docker-patterns` — multi-stage build, sécurité conteneur

### 6.2 Configurer le déploiement

```
Crée la configuration de déploiement :
1. application-prod.yml (configuration production)
2. Script de déploiement avec rollback
3. Health check endpoint personnalisé
4. Logging structuré (JSON) pour la production
```

> **Skill** : `deployment-patterns` — CI/CD, rollback, health checks

### 6.3 Configurer Spring Security

```
Configure Spring Security pour MarkdownVault :
1. Authentification par formulaire (login/logout)
2. Utilisateur en mémoire pour le développement
3. Protection CSRF sur tous les formulaires
4. Headers de sécurité (CSP, X-Frame-Options, HSTS)
5. Endpoint /api/** accessible en session uniquement
6. Pages statiques (CSS/JS) accessibles sans auth
```

> **Skill** : `springboot-security`  
> **Rule** : `security-baseline`

---

## Étape 7 — Finalisation et validation

### 7.1 Revue adverse finale (Santa Method)

```
Lance une revue adverse complète de l'application MarkdownVault.
Deux reviewers indépendants doivent tous les deux approuver avant merge.
Focus : sécurité, performance, maintenabilité, accessibilité.
```

> **Pipeline** : `santa-method` — double revue adverse avec convergence  
> **Skills** : `security-review`, `springboot-verification`, `accessibility`

### 7.2 Documentation

```
/update-docs

Mets à jour la documentation :
1. README.md avec instructions de build et déploiement
2. API documentation (endpoints, exemples curl)
3. Guide utilisateur (comment importer, organiser, rechercher)
4. ADR mis à jour avec toutes les décisions prises
```

> **Workflow** : `/update-docs`  
> **Skill** : `architecture-decision-records`

### 7.3 Audit du harnais agentique

```
/harness-audit

Audite le cadre agentique utilisé pendant le développement :
- Quels skills ont été les plus utiles ?
- Quels workflows ont été invoqués ?
- Combien de tokens consommés ?
- Recommandations pour les prochains projets
```

> **Workflow** : `/harness-audit`

### 7.4 Statistiques de session

Pour conclure, observons l'activité de l'agent pendant toute la session :

```bash
.agents/scripts/ea-logger stats
```

Sortie attendue :

```
📊 Agent Activity — 2026-05-10
────────────────────────────────────────────────────────────────
  Total calls : 47
  Session     : 09:15:02 → 17:42:38

  Type          Calls
  ──────────── ──────
  HOOK              8
  PIPELINE          7
  RULE             12
  SKILL            14
  WORKFLOW          6

  Top 10 resources:
     5x  springboot-patterns
     4x  security-review
     3x  jpa-patterns
     3x  tdd-workflow
     2x  /code-review
     2x  /build-fix
     2x  hexagonal-architecture
     2x  springboot-tdd
     1x  /plan
     1x  /feature-dev
```

> **Skill** : `log-viewer` — l'agent explique les statistiques

---

## Récapitulatif des interactions avec l'agent (Spring Boot)

| Étape | Ce que vous demandez | Ce que l'agent fait | Composants mobilisés |
|---|---|---|---|
| 1.1 | Plan d'architecture | Génère la structure hexagonale | `/plan` + `springboot-patterns` + `hexagonal-architecture` |
| 1.2 | Conseil d'architecture | 4 voix débattent du stockage | `council` (pipeline) |
| 1.3 | Décision ADR | Documente le choix | `architecture-decision-records` |
| 2.1 | Entités JPA | Génère les entités avec validations | `jpa-patterns` + `java-coding-standards` |
| 2.2 | Tests TDD | Écrit les tests avant le code | `tdd-cycle` (pipeline) + `springboot-tdd` |
| 2.3 | Correction build | Corrige Gradle/Maven | `/build-fix` + `bash-safety` (hook) |
| 2.4 | Migration | Flyway V1 | `database-migrations` + `postgres-patterns` |
| 3.1 | Service CRUD | Architecture hexagonale | `/feature-dev` + `hexagonal-architecture` |
| 3.2 | Contrôleur REST TDD | MockMvc → implémentation | `tdd-cycle` + `api-design` |
| 3.3 | Revue multi-agents | Convergence 2 reviewers | `code-review` (pipeline) + `security-review` |
| 3.4 | Couverture | Analyse JaCoCo + tests manquants | `/test-coverage` |
| 4.1 | Import curl.md | RestClient + hexagonal | `springboot-patterns` + `api-design` |
| 4.2 | Sécurité import | SSRF, rate limiting, sanitization | `springboot-security` + `security-review` |
| 4.3 | Tests import | WireMock + Testcontainers | `tdd-cycle` + `springboot-tdd` |
| 5.1 | Interface Thymeleaf | Vues responsives + accessible | `/feature-dev` + `accessibility` + `seo` |
| 5.3 | Qualité globale | Build + tests + sécurité | `/quality-gate` + `code-review` (pipeline) |
| 6.1 | Docker | Multi-stage + compose | `docker-patterns` |
| 6.3 | Sécurité Spring | Auth + CSRF + headers | `springboot-security` |
| 7.1 | Revue finale | Double revue adverse | `santa-method` (pipeline) |
| 7.2 | Documentation | README + API doc + ADR | `/update-docs` + `architecture-decision-records` |

## Différences pédagogiques avec l'exemple Symfony

| Aspect | Exemple Symfony (chap. 3) | Exemple Spring Boot (chap. 4) |
|---|---|---|
| **Skills** | 6 skills | **22 skills** |
| **Workflows** | 4 workflows | **10 workflows** |
| **Pipelines** | aucun | **4 pipelines** (TDD, code-review, council, santa) |
| **Architecture** | MVC classique | **Hexagonale** (Ports & Adapters) |
| **Tests** | Tests basiques | **TDD strict** (red-green-refactor) |
| **Sécurité** | Vérification ponctuelle | **Audit systématique** + revue adverse |
| **Décisions** | Implicites | **ADR documentés** |
| **Logging** | Non observé | **Statistiques de session complètes** |

---

> **Rappel** : le développement agentique ne remplace pas votre réflexion.
> L'agent est un **assistant puissant**, mais c'est vous le développeur.
> Comprenez ce qu'il fait, apprenez de ses suggestions, et gardez toujours
> un esprit critique.
