# Targie

[English](README.md) | [简体中文](README_ZH.md) | [繁體中文](README_ZH_HANT.md) | [Español](README_ES.md)

> **macOS uniquement.** Targie est une application native pour macOS 14+. Il n'existe pas de version Windows ni Linux, et aucune n'est prévue.

Targie trouve des vidéos et des images similaires dans les dossiers sélectionnés en combinant métadonnées, hachages de contenu, empreintes perceptuelles et caractéristiques visuelles.

## Fonctionnalités

- Bascule entre les modes de scan Vidéos, Images et Tous, et mémorise le mode sélectionné.
- Ajoute plusieurs dossiers via le sélecteur ou par glisser-déposer depuis le Finder, puis compare les médias dans tous les dossiers sélectionnés.
- Analyse récursivement les formats vidéo courants ainsi que les images JPEG, PNG, HEIC, HEIF, WebP, TIFF, GIF et BMP.
- Utilise SHA-256, des empreintes perceptuelles mises en cache, des métadonnées et des fonctionnalités Vision réutilisables, en isolant les fichiers illisibles.
- Sépare les groupes de vidéos et d'images pour une comparaison côte à côte avec des aperçus statiques intégrés.
- Ouvre les vidéos dans le lecteur par défaut et révèle tout type de média dans le Finder.
- Prend en charge la sélection multiple explicite et la suppression par lots avec succès partiel.
- Exige un choix explicite entre déplacer vers la Corbeille et supprimer définitivement, avec une seconde confirmation pour la suppression permanente.
- Prend en charge l'anglais, le chinois simplifié, le chinois traditionnel, l'espagnol et le français avec changement instantané et préférence mémorisée.
- **Mode parcourir** : affiche tous les fichiers des dossiers sélectionnés dans un tableau triable et filtrable, avec colonnes redimensionnables par glissement, sélection par lots et titre de fenêtre mis à jour en temps réel.

![Comparaison de similarité d'images](asset/Screenshot1.png)

![Comparaison de similarité de vidéos](asset/Screenshot2.png)

![Mode parcourir — liste de fichiers avec aperçu](asset/Screenshot3.png)

## Compilation (macOS uniquement)

```bash
swift test
./script/build_app.sh
```

L'application générée se trouve dans :

```text
dist/Targie.app
```

Pour le développement, compilez et lancez avec :

```bash
./script/build_and_run.sh
```

L'application est signée de manière ad-hoc pour un usage local. La distribution via Internet ou l'App Store nécessite un Developer ID, une notarisation et le processus d'empaquetage approprié.

## Licence

Targie est sous licence **[GNU General Public License v3.0](LICENSE)**.

Copyright (C) 2026 Lirui Yu.

Si vous réutilisez ce code (modifié ou non) :

- Vous **devez** conserver la mention de copyright et créditer l'auteur original (Lirui Yu).
- Toute œuvre dérivée que vous distribuez **doit** également être publiée sous GPL-3.0 (ou une version ultérieure de la GPL), avec le code source complet disponible pour ses utilisateurs.
- La redistribution en code fermé ou propriétaire **n'est pas** autorisée.

Consultez le fichier [LICENSE](LICENSE) pour le texte juridique complet.

## Contribution

Les pull requests sont les bienvenues. Chaque commit doit être signé sous le [Developer Certificate of Origin (DCO)](DCO) — passez `-s` à `git commit`. Voir [CONTRIBUTING.md](CONTRIBUTING.md) pour plus de détails.
