# Lumo macOS v0.14.2 — Hybrid Agent

## Nouveautés
- Mode IA **Automatique** par défaut : Gemini 2.5 Flash-Lite planifie, Claude Haiku exécute les outils macOS et sert de fallback de planification.
- Modes : **Économique**, **Automatique**, **Claude uniquement**.
- Clé Gemini stockée séparément dans le Trousseau macOS.
- Boutons de test Gemini et Claude dans Réglages > IA.
- Contexte Claude réduit aux 8 derniers messages et budget de sortie réduit afin de limiter le coût des boucles procédurales.
- Le moteur procédural, les outils fichiers, Terminal, Accessibility, permissions et animations de v0.13 sont conservés.

## Important
Le mode Économique utilise Gemini pour la planification, mais Claude reste actuellement le moteur d'exécution des tool calls macOS. C'est volontaire : cela conserve la compatibilité complète avec le registre d'outils existant tout en réduisant déjà le coût de planification. Une future étape peut porter l'exécuteur outillé lui-même vers Gemini.

## Démarrage
1. Ouvrir `Lumo.xcodeproj`.
2. Réglages > IA : renseigner une clé Gemini et une clé Anthropic.
3. Choisir **Automatique — Gemini + Claude**.
4. Tester les deux connexions.

## v0.14.2.2
- Corrige l'appel `async` dans l'opérateur `??` du mode Automatique : fallback Gemini → Claude désormais séquentiel et compatible Swift Concurrency.
- Supprime les `await` inutiles sur les callbacks `@MainActor` synchrones.

## v0.14.2 — Task Monitor
- Journal d'exécution procédural en temps réel dans la bulle Lumo.
- Affiche planification, action courante, résultat, succès/échec et durée.
- Affiche le temps écoulé de la mission.
- Bouton Arrêter dédié pendant une mission.
- Les commandes shell sont exécutées hors du thread UI afin de ne plus figer la bulle pendant `pip`, `python`, `xcodebuild`, etc.
- Les sorties d'outils sont résumées dans le journal (jusqu'à 1200 caractères par événement).

## Icône et installateur

La version inclut l'icône Lumo dans `Lumo/Assets.xcassets/AppIcon.appiconset` et un générateur de DMG dans `Installer/build-installer.command`. Sur macOS, exécuter ce fichier pour produire `dist/Lumo-Installer.dmg` avec la présentation Lumo → Applications.

## v0.16 — Deterministic Executor

- Gemini génère en un seul appel un plan JSON directement exécutable.
- Les actions déterministes sont ensuite exécutées localement par Swift, sans nouvel appel LLM entre chaque étape.
- `write_text_file` relit désormais le fichier et compare exactement son contenu avant d'annoncer un succès.
- Blocage des actions identiques déjà réussies dans le fallback Claude.
- Le fallback Claude est limité à 30 tours et interrompt automatiquement les boucles répétitives.
- Le mode Économique peut fonctionner sans clé Anthropic lorsque Gemini suffit à la mission.
- Le Task Monitor affiche `Étape n/N` pendant l'exécution locale.
