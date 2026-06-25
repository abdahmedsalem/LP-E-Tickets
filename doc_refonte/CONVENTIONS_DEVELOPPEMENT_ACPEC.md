# Conventions de développement ACPEC

Document de référence pour le développement ACPEC, lisible par un humain et par un agent IA.
Énonce des règles à identifiant stable. Une implémentation conforme respecte toutes les
règles applicables.

```text
---
doctrine: conventions-developpement-acpec
version_doctrine: 1.0
statut: actif
auteur: ACPEC SARL
website: https://apcec.odoorim.com      # À CONFIRMER : "apcec" diffère de "acpec" utilisé partout ailleurs
licence: OPL-1
odoo_version: NON SPÉCIFIÉE              # À RENSEIGNER ; voir CONV-VER-2
principe_resolution_conflit: demander-avant-supposer
priorite: [securite > correction > lisibilite > concision]
---
```

---

## 1. Lisibilité

### Principes

Le code ACPEC est optimisé pour la lecture humaine, pas pour l'élégance ou la concision
maligne. Un développeur qui découvre le code doit le comprendre sans le décoder.

### Règles

```text
CONV-LIS-1  Préférer le code explicite et direct au code clever. Une solution plus longue
            mais évidente est préférée à une solution courte mais astucieuse.
CONV-LIS-2  Noms parlants pour variables, méthodes et champs ; pas d'abréviations obscures.
CONV-LIS-3  Une intention non évidente est expliquée par un commentaire court.
CONV-LIS-4  Éviter les effets de bord cachés et les raccourcis qui exigent de connaître
            un détail non écrit pour être compris.
CONV-LIS-5  Respecter les conventions de code Odoo : style idiomatique du framework,
            patterns ORM standard, décorateurs api appropriés, structure de module
            habituelle. Du code Odoo doit ressembler à du code Odoo.
CONV-LIS-6  Pas d'annotations de type Python sauf si elles clarifient réellement une
            signature non évidente. Le style suit le code Odoo standard, qui n'en
            utilise pas. Le défaut est : aucune annotation.
```

---

## 2. Nommage

### Principes

Tout ce qui appartient à ACPEC est préfixé de façon homogène, pour se distinguer
immédiatement du standard Odoo.

### Règles

```text
CONV-NOM-1  Tout module ACPEC commence par "acpec_" (ex. acpec_mobile_auth).
CONV-NOM-2  Tout modèle custom ACPEC commence par "acpec." (ex. acpec.fuel.wallet).
CONV-NOM-3  Tout champ ajouté à un modèle Odoo standard est préfixé "acpec_"
            (ex. acpec_mobile_phone sur res.users).
CONV-NOM-4  Les noms techniques — modèles, champs, méthodes, variables, fichiers — sont
            en anglais (voir CONV-LANG-2).
```

---

## 3. Langue

### Principes

L'interface est en français ; la technique est en anglais. Le français est la langue
source des traductions.

### Règles

```text
CONV-LANG-1  Tout texte vu par l'utilisateur — libellés, messages, aides, titres,
             notifications — est en français.
CONV-LANG-2  Tout élément technique — noms de modèles, champs, méthodes, variables,
             commentaires de code, journaux techniques — est en anglais.
CONV-LANG-3  Les chaînes destinées à l'utilisateur sont enveloppées par _() lorsque le
             contexte Odoo le permet, pour activer la traduction.
CONV-LANG-4  La langue source est le français. Les traductions (arabe, anglais) dérivent
             du français, jamais l'inverse.
CONV-LANG-5  Si un chemin n'a pas de contexte de traduction fiable (appel hors session
             utilisateur), une chaîne française littérale est acceptable et documentée.
```

---

## 4. Métadonnées des modules

### Règles

```text
CONV-MOD-1  Tout manifeste de module ACPEC déclare :
            author  = "ACPEC SARL"
            website = "https://apcec.odoorim.com"   # voir note en-tête
            license = "OPL-1"
CONV-MOD-2  Ces valeurs sont identiques dans tous les modules ACPEC.
```

---

## 5. Interface utilisateur

### Principes

L'UI ACPEC est professionnelle : robuste, homogène, sobre, intuitive.

### Règles

```text
CONV-UI-1  Robuste  : l'UI gère les cas vides, les erreurs et les états d'attente sans
           casser ni laisser l'utilisateur sans retour.
CONV-UI-2  Homogène : mêmes motifs, mêmes libellés, même disposition pour des actions
           équivalentes d'un écran à l'autre.
CONV-UI-3  Sobre    : pas de surcharge visuelle ; l'essentiel d'abord.
CONV-UI-4  Intuitive: le chemin nominal est évident sans documentation.
CONV-UI-5  Toute décision de sécurité reste côté backend ; l'UI ne fait qu'afficher
           l'état que le backend impose (cohérent avec la doctrine de sécurité).
```

---

## 6. Versions Odoo

### Principes

Le comportement d'Odoo varie selon la version. On ne suppose pas ; on vérifie.

### Règles

```text
CONV-VER-1  Pour toute adaptation dépendante de la version d'Odoo, consulter le code
            source officiel d'Odoo (GitHub) de la version cible avant de coder.
CONV-VER-2  Si la version d'Odoo n'est pas précisée dans la documentation ou la demande,
            la demander avant de proposer un patch. Ne pas la supposer.
CONV-VER-3  Toute API ou comportement spécifique à une version est noté avec la version
            concernée, pour qu'une montée de version repère les points à revérifier.
```

---

## 7. Méthode de travail de l'agent

### Principes

L'agent ne code pas à l'aveugle. Il s'aligne sur l'environnement et la doctrine avant de
produire, et laisse l'application des patches à l'humain.

### Règles

```text
CONV-WORK-1  Avant de travailler, demander : l'environnement de dev, les répertoires du
             projet, et les commandes d'exécution d'Odoo et de Flutter.
CONV-WORK-2  Avant tout patch : extraire et lire le code réel concerné. Ne pas se fier à
             la mémoire d'un état antérieur.
CONV-WORK-3  Avant tout patch : lire la ou les doctrines applicables et s'y conformer.
CONV-WORK-4  Livrer les patches pour application MANUELLE par l'humain ; ne pas présumer
             qu'ils sont appliqués.
CONV-WORK-5  Toujours vérifier : confronter ce qui est proposé au code réel et à la
             doctrine, et signaler tout écart, contradiction ou risque, même non demandé.
CONV-WORK-6  En cas de doute, d'ambiguïté ou d'information manquante : demander avant de
             supposer (principe de résolution de conflit de l'en-tête).
```

---

## 8. Anti-patterns (interdits)

```text
ANTI-A1  Code clever au détriment de la lisibilité (contre CONV-LIS-1).
ANTI-A9  Code non idiomatique Odoo, ou annotations de type superflues (contre CONV-LIS-5/6).
ANTI-A2  Texte utilisateur en anglais, ou nom technique en français (contre CONV-LANG-1/2).
ANTI-A3  Champ sur un modèle standard sans préfixe acpec_ (contre CONV-NOM-3).
ANTI-A4  Module ou modèle custom sans préfixe acpec (contre CONV-NOM-1/2).
ANTI-A5  Supposer une version d'Odoo non précisée (contre CONV-VER-2).
ANTI-A6  Appliquer ou présumer appliqué un patch au lieu de le livrer pour revue manuelle
         (contre CONV-WORK-4).
ANTI-A7  Coder sans avoir lu le code réel ni la doctrine (contre CONV-WORK-2/3).
ANTI-A8  Décision de sécurité côté frontend (contre CONV-UI-5).
```

---

## 9. Checklist de conformité

```text
Une contribution est conforme si et seulement si :
[ ] modules en acpec_*, modèles custom en acpec.*, champs standard en acpec_* ;
[ ] UI en français via _() quand possible ; technique en anglais ;
[ ] manifeste : author ACPEC SARL, website officiel, licence OPL-1 ;
[ ] version d'Odoo connue ; adaptations spécifiques vérifiées sur la source officielle ;
[ ] code lisible, explicite, commenté là où l'intention n'est pas évidente ;
[ ] code idiomatique Odoo, sans annotations de type superflues ;
[ ] UI robuste, homogène, sobre, intuitive ;
[ ] code réel et doctrine lus avant production ;
[ ] patch livré pour application manuelle, écarts signalés ;
[ ] aucun anti-pattern (§8) présent.
```
