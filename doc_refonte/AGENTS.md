# AGENTS.md — Instructions pour tout agent travaillant sur ACPEC FuelToken

Ce fichier est chargé en premier. Il impose le protocole de travail. Le respecter n'est
pas optionnel. Pour Claude Code, le copier aussi en `CLAUDE.md` ; pour Cursor, en
`.cursorrules`.

## Point d'entrée

Avant toute chose, lire `doc_refonte/00_index.md` depuis la racine du dépôt
ou `00_index.md` depuis ce dossier. Il liste les doctrines, leur portée,
leur priorité en cas de conflit, et indique lesquelles s'appliquent à une tâche donnée.

## Protocole obligatoire avant tout patch

```text
1. DEMANDER ce qui manque : version d'Odoo, environnement de dev, répertoires du projet,
   commandes d'exécution Odoo et Flutter. Ne rien supposer (CONV-WORK-1, CONV-VER-2).
2. EXTRAIRE et LIRE le code réel concerné. Ne pas se fier à la mémoire (CONV-WORK-2).
3. LIRE la ou les doctrines applicables (via 00_index) et s'y conformer (CONV-WORK-3).
4. PRODUIRE le patch en citant les INV-* qu'il implémente.
5. LIVRER le patch pour application MANUELLE. Ne jamais présumer qu'il est appliqué
   (CONV-WORK-4).
6. VÉRIFIER : confronter au code réel et à la doctrine ; signaler tout écart,
   contradiction ou risque, même non demandé (CONV-WORK-5).
```

## Règles de fer

```text
- En cas de doute, d'ambiguïté ou d'information manquante : DEMANDER, ne pas supposer.
- En cas de conflit entre règles : appliquer l'ordre de priorité du 00_index.
- En cas de doute sur une autorisation de sécurité : refuser (fail-closed).
- Une difficulté de test ne justifie jamais d'affaiblir un contrôle : simuler l'entrée
  (doctrine mode dev/test §4).
- Tout code suit les conventions ACPEC (CONVENTIONS_DEVELOPPEMENT_ACPEC.md) :
  modules acpec_*, modèles acpec.*, champs standard acpec_*, UI en français via _(),
  technique en anglais, code lisible et idiomatique Odoo, pas d'annotations de type
  superflues.
```

## Langues

Règle générale : utilisateur métier en français, éléments techniques dev/API en anglais.

- model names : anglais
- field names : anglais
- enum keys : anglais
- API error codes : anglais
- Python method names : anglais
- XML ids : anglais
- menu/action/view labels : français
- field string/help : français
- messages affichés à Flutter : français
- messages techniques dans logs : anglais ou mixte, avec clés techniques stables

Exemple log serveur :

mobile_api_server_error reference=ERR-... endpoint=... exception_type=...

Exemple UI Odoo :

Incidents API mobile
Nombre d’occurrences
Dernière apparition



## Définition de « terminé »

Un travail n'est terminé que si :

```text
[ ] chaque INV-* visé a un test qui le vérifie, et le test cite l'ID de l'invariant ;
[ ] la table `doc_refonte/traceability.md` est mise à jour (INV-* -> code -> test) ;
[ ] la checklist de conformité de chaque doctrine applicable est cochée avec preuve ;
[ ] aucun anti-pattern (ANTI-*) présent ;
[ ] le patch est livré pour revue manuelle, écarts signalés.
```

Une affirmation de conformité sans test qui la prouve n'est pas une conformité.
