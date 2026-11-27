# PreuvCam

PreuvCam est une dashcam à preuve d'intégrité, réalisée pour le cours de Cloud Computing du Master MIAGE (Université de Haute-Alsace, 2026).

Le téléphone du conducteur filme la route en segments de 10 secondes. Pour chaque segment, il calcule une empreinte SHA-256, la chaîne à l'empreinte précédente et l'envoie dans le cloud. Les vidéos restent sur le téléphone. Après un accident, le conducteur transmet les segments utiles à son assureur, qui vérifie dans le cloud qu'ils n'ont pas été modifiés, qu'aucun segment ne manque, à quel moment chacun a été filmé et s'ils ont été envoyés à temps.

Le projet comprend deux applications :

| Application | Utilisateur | Plateforme |
| --- | --- | --- |
| PreuvCam | Le conducteur | Android |
| PreuvCam Assureur | L'agent de la compagnie d'assurance | Navigateur web, ordinateur ou téléphone |

Démonstration du décodeur : [epsi12-lab.github.io/Dashcam](https://epsi12-lab.github.io/Dashcam/) (comptes de démonstration sur demande).

## Architecture

```
Téléphone Android (PreuvCam)          Supabase (cloud, Paris)       Navigateur (PreuvCam Assureur)
 caméra, segments de 10 s     ──▶   PostgreSQL + RLS          ◀──   vérification des vidéos
 SHA-256, chaînage, file locale      Auth, temps réel, pg_cron        suivi en direct
 rétention locale, export            purge des empreintes             gel des empreintes
```

Seules les empreintes (quelques centaines d'octets par segment) passent par le réseau. Les vidéos ne quittent le téléphone que lorsque le conducteur les exporte. Le décodeur calcule les empreintes des fichiers reçus dans le navigateur, sans les envoyer nulle part.

## Organisation du dépôt

| Dossier | Contenu |
| --- | --- |
| `packages/dashcam_core` | Code Dart commun : hachage, nommage des segments, règles de vérification |
| `apps/encoder` | PreuvCam, l'application Android du conducteur (Flutter) |
| `apps/decoder` | PreuvCam Assureur, l'application web de l'assureur (Flutter Web) |
| `supabase` | Migrations SQL, données de démonstration, tests pgTAP |
| `tools/demo_segments` | Simulateur qui produit des segments et leurs empreintes sans téléphone |
| `docs` | Schéma de la base (PlantUML) |
| `.github/workflows` | Intégration continue et publication du décodeur |

## Prérequis

Les versions ci-dessous sont celles utilisées pour le développement. Elles sont figées dans la CI.

| Outil | Version |
| --- | --- |
| Flutter | 3.38.9 (Dart 3.10.8) |
| Supabase CLI | 3.0.0 |
| Docker | Docker Engine avec Docker Compose |
| Android | Un téléphone Android avec le débogage USB activé, et `adb` |
| Navigateur | Chrome ou Chromium |

Le projet a été développé sous Ubuntu. iOS n'est pas pris en charge (pas de Mac pour compiler).

## Configuration

Chaque application lit sa configuration au moment de la compilation, dans un fichier `env/<nom>.json` passé avec `--dart-define-from-file`. Ces fichiers sont ignorés par Git : créez-les vous-même.

PreuvCam (`apps/encoder/env/dev.json`) :

```json
{
  "SUPABASE_URL": "http://127.0.0.1:54321",
  "SUPABASE_KEY": "sb_publishable_...",
  "PROFILE": "demo"
}
```

PreuvCam Assureur (`apps/decoder/env/dev.json`) :

```json
{
  "SUPABASE_URL": "http://127.0.0.1:54321",
  "SUPABASE_KEY": "sb_publishable_..."
}
```

`dev.json` pointe vers la pile locale, `cloud.json` vers le projet Supabase hébergé (même format, avec l'URL et la clé du projet). La clé à utiliser est toujours la clé publique (`sb_publishable_...`). La clé secrète ne doit jamais apparaître dans une application ni dans le dépôt.

`PROFILE` n'existe que dans PreuvCam. Avec la valeur `demo`, la rétention locale des vidéos passe de 24 heures à 2 minutes, pour que la purge soit visible pendant une démonstration.

## Installation locale

### 1. Base de données

Le réseau Docker est limité à `127.0.0.1`, pour que les ports de Supabase ne soient pas exposés sur le réseau local (les ports publiés par Docker contournent le pare-feu `ufw`). Toutes les commandes qui lancent des conteneurs doivent recevoir l'option `--network-id`. Un alias évite de l'oublier :

```bash
# Une seule fois
docker network create -o 'com.docker.network.bridge.host_binding_ipv4=127.0.0.1' local-network
alias sb='supabase --network-id local-network'

# Démarrer Supabase, puis reconstruire la base à partir des migrations
sb start
sb db reset
```

`db reset` applique les migrations puis `supabase/seed.sql`, qui crée deux compagnies et quatre comptes :

| Compte | Rôle | Compagnie |
| --- | --- | --- |
| `conducteur1@alpha.test` | Conducteur | Assur Alpha |
| `conducteur2@alpha.test` | Conducteur | Assur Alpha |
| `agent@alpha.test` | Agent | Assur Alpha |
| `agent@beta.test` | Agent | Assur Beta |

Le mot de passe de démonstration local est défini dans `seed.sql`. Il ne doit jamais être réutilisé dans le cloud. La clé publique locale s'affiche avec `supabase status`.

### 2. PreuvCam (téléphone)

```bash
cd apps/encoder
adb reverse tcp:54321 tcp:54321
flutter run --dart-define-from-file=env/dev.json
```

`adb reverse` permet au téléphone de joindre la pile locale par le câble USB. La configuration réseau qui autorise HTTP vers `127.0.0.1` n'existe que dans la version de débogage : la version de production n'accepte que HTTPS.

### 3. PreuvCam Assureur (navigateur)

```bash
cd apps/decoder
flutter run -d web-server --dart-define-from-file=env/dev.json
```

Ouvrez l'adresse affichée dans le terminal. L'option `web-server` évite un plantage de Chrome installé en snap. En mode `web-server`, les erreurs de l'application s'affichent dans la console du navigateur (F12), pas dans le terminal.

### 4. Simulateur (facultatif)

Pour tester le décodeur sans téléphone, le simulateur se connecte comme conducteur, enregistre un téléphone neuf et produit un segment toutes les 10 secondes :

```bash
cd tools/demo_segments
export SUPABASE_URL=http://127.0.0.1:54321
export SUPABASE_KEY=sb_publishable_...
export DEMO_EMAIL=conducteur1@alpha.test
export DEMO_PASSWORD=...
dart run bin/demo_segments.dart --count 5                        # jeu normal
dart run bin/demo_segments.dart --count 5 --out demo_late --late  # dernier envoi retardé
```

## Tests

| Partie | Commande | Contenu |
| --- | --- | --- |
| Code commun | `cd packages/dashcam_core && dart test` | Hachage, nommage, verdicts, période filmée |
| PreuvCam | `cd apps/encoder && flutter test --exclude-tags integration` | File locale, envoi, rétention, export |
| PreuvCam Assureur | `cd apps/decoder && flutter test --exclude-tags integration` | Service de vérification |
| Base | `sb test db` | Contraintes, droits d'accès, purge (pgTAP) |

Les tests d'intégration des deux applications portent l'étiquette `integration`. Ils nécessitent la pile locale démarrée et se lancent avec `flutter test --tags integration`.

## Intégration et publication continues

| Workflow | Déclenchement | Rôle |
| --- | --- | --- |
| `ci.yml` | Chaque push sur `main` et chaque pull request | Analyse statique stricte et tests : code commun, base (pgTAP), PreuvCam, PreuvCam Assureur |
| `pages.yml` | Push sur `main` qui touche le décodeur ou le code commun | Construction de PreuvCam Assureur et publication sur GitHub Pages |

Les versions des outils sont figées, et chaque workflow ne reçoit que les droits dont il a besoin. Pour la publication, l'URL et la clé publique de Supabase sont des variables du dépôt (`Settings`, puis `Secrets and variables`, puis `Actions`, onglet `Variables`), lues par le job de construction.

## Déploiement dans le cloud

1. Créez un projet sur [supabase.com](https://supabase.com), dans une région de l'Union européenne. À la création, décochez « Grant API access to new tables automatically » et cochez « Enable RLS on new tables automatically ».
2. Liez le dépôt et poussez les migrations, en simulant d'abord :

```bash
supabase login
supabase link --project-ref <référence-du-projet>
supabase db push --remote --dry-run
supabase db push --remote
```

Sans `--remote`, la CLI 3 vise la pile locale.

3. Créez les comptes : copiez `supabase/seed.sql` dans le SQL Editor du tableau de bord, remplacez le mot de passe de démonstration par un mot de passe propre au cloud, exécutez, puis fermez l'onglet sans l'enregistrer.
4. Créez `env/cloud.json` dans chaque application, avec l'URL et la clé publique du projet.

### PreuvCam, installable sans ordinateur

```bash
cd apps/encoder
flutter build apk --release --dart-define-from-file=env/cloud.json
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

La version de production est signée avec la clé de débogage du modèle Flutter : c'est suffisant pour une démonstration, pas pour une publication sur le Play Store. Les mesures de performance doivent être faites avec cette version, nettement plus rapide que le mode debug.

### PreuvCam Assureur, sur GitHub Pages

Le workflow `pages.yml` construit et publie le décodeur automatiquement. Pour une construction manuelle :

```bash
cd apps/decoder
flutter build web --release --base-href /Dashcam/ \
  --dart-define=SUPABASE_URL=https://<référence>.supabase.co \
  --dart-define=SUPABASE_KEY=sb_publishable_...
```

L'option `--base-href` est indispensable, puisque le site est publié dans le sous-dossier `/Dashcam/`. La clé publique est visible dans le code publié, c'est prévu : les données sont protégées par la RLS, pas par le secret de cette clé. Après une nouvelle publication, un navigateur peut garder l'ancienne version en cache : faites un rechargement forcé (Ctrl+Maj+R).

## Sécurité

Chaque table a la RLS activée, et les droits sont accordés colonne par colonne. Un conducteur n'insère que ses propres empreintes et ne peut pas fixer l'heure de réception, qui est attribuée par le serveur. Un agent ne voit que les téléphones et les empreintes de sa compagnie, y compris par le canal temps réel. Aucun rôle applicatif ne peut supprimer une empreinte, et le gel d'une empreinte par l'assureur est irréversible. Les empreintes non gelées sont purgées après 30 jours par une tâche `pg_cron`.

## Limites connues et évolutions

L'enregistrement s'arrête quand PreuvCam passe en arrière-plan : filmer en arrière-plan demanderait un service Android de premier plan. Une capture d'écran ou le volet de notifications ne coupent pas l'enregistrement. Après une courte absence, il reprend seul ; après une longue absence, il faut toucher « Démarrer ». Environ une demi-seconde est perdue entre deux segments. Le débit vidéo est imposé par le profil du constructeur du téléphone, d'où un quota de 2 Go pour les vidéos locales.

Les comptes sont aujourd'hui créés par l'opérateur de la plateforme. L'évolution prévue est la création du compte conducteur par l'agent de sa compagnie, depuis PreuvCam Assureur, au moyen d'une Edge Function qui garde la clé secrète côté serveur.

## Auteur

Bruce Tumpa Madila, M1 MIAGE, Université de Haute-Alsace, 2026.
