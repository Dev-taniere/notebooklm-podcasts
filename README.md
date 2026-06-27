# notebooklm-podcasts

Flux RSS privé (public, non listé) des aperçus audio générés par **NotebookLM**.
Hébergé via **GitHub Pages**. S'abonner dans une app de podcast (AntennaPod, Apple Podcasts) :

**URL du flux :** https://dev-taniere.github.io/notebooklm-podcasts/feed.xml

## Mettre à jour (ajouter les nouveaux podcasts)
```bash
~/notebooklm-podcasts/update.sh
```
Le script détecte les nouveaux aperçus audio du notebook, les télécharge, régénère `feed.xml` et pousse.
