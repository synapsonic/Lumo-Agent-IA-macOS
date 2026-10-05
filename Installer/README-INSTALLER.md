# Installateur Lumo

L'icône Lumo est déjà intégrée au target Xcode via `Assets.xcassets/AppIcon.appiconset`.

## Générer `Lumo-Installer.dmg`

Sur le Mac de développement :

1. Ouvrir le dossier `Installer`.
2. Double-cliquer `build-installer.command`.
3. Le script compile Lumo en Release, signe localement l'application, puis crée `dist/Lumo-Installer.dmg`.
4. Dans le DMG, l'utilisateur glisse **Lumo.app** vers **Applications**.

### Distribution publique signée

Pour une distribution hors de ton Mac, définir une identité Developer ID avant d'exécuter le script :

```bash
export LUMO_SIGN_IDENTITY="Developer ID Application: VOTRE NOM (TEAMID)"
./Installer/build-installer.command
```

Une distribution publique propre nécessite ensuite la notarisation Apple. Le script utilise sinon une signature ad hoc, adaptée aux tests locaux mais pas à une diffusion publique sans avertissement Gatekeeper.
