# Doctrine mode développement / test — FuelToken V1

Complément de la *Doctrine de sécurité mobile FuelToken V1*. Définit ce que le mode
développement autorise, ce qu'il n'autorise jamais, et comment produire des variations
de test sans affaiblir la sécurité. La classification d'environnement et la porte unique
sont régies par la doctrine runtime fail-closed (Patch36A), à laquelle ce document se
conforme.

---

## 0. Principe directeur

Production / sécurité stricte est le comportement par défaut. Le mode développement
n'existe que par assertion positive d'environnement, derrière une porte unique.

La règle qui structure tout ce document :

```text
Le mode développement SIMULE des ENTRÉES.
Il ne CONTOURNE jamais un CONTRÔLE.
```

Simuler une entrée, c'est fabriquer une condition d'essai par les chemins légitimes
(un autre identifiant d'appareil, un état d'appareil posé en back-office, un OTP de test).
Contourner un contrôle, c'est faire répondre « autorisé » à une vérification qui devrait
refuser. La première est nécessaire pour tester ; la seconde transforme le test en preuve
d'un système qui n'est pas celui de production.

---

## 1. Porte unique

### Principes

Une seule fonction décide si les facilités de développement sont actives. Toute facilité
passe par elle ; aucune décision de relaxation ne s'appuie sur autre chose.

### Invariants

```text
INV-DEV-1  Les facilités de développement ne sont actives que si l'environnement est
           explicitement de type développement ET le drapeau maître dev est positionné.
           Tout autre cas — production, environnement absent, inconnu, contradictoire —
           force le mode strict.
INV-DEV-2  Aucune facilité ne dépend de la négation d'un état de production ; elle dépend
           uniquement de l'autorisation positive de la porte dev.
INV-DEV-3  Le mécanisme de test natif d'Odoo n'active jamais à lui seul une facilité dev.
INV-DEV-4  Si l'état est strict alors qu'une configuration dev traîne, le readiness le
           signale ; la sûreté reste garantie par le refus de relaxer.
```

### Tests

```text
T-DEV-1  Environnement de production + drapeau dev => mode strict.
T-DEV-2  Environnement absent ou inconnu + drapeau dev => mode strict + readiness.
T-DEV-3  Environnement dev + drapeau absent => mode strict.
T-DEV-4  Environnement dev + drapeau actif => mode dev.
```

---

## 2. Ce que le mode développement autorise (liste blanche)

### Principes

Les facilités autorisées réduisent la friction d'essai sans toucher à la valeur ni à
l'identité. Elles sont inoffensives par construction.

### Invariants

```text
INV-DEV-5  Sous porte dev active, et seulement alors, sont autorisés :
           - OTP simulé par code fixe, sans envoi SMS réel ;
           - désactivation des limitations de débit OTP ;
           - transport local en clair (boucle locale) ;
           - jeux de données et scénarios de test ;
           - journalisation technique plus verbeuse, secrets toujours masqués.
INV-DEV-6  L'OTP simulé reste soumis à l'expiration et au blocage du challenge :
           la facilité de délivrance ne relaxe pas les invariants par challenge.
INV-DEV-7  Aucune valeur secrète (OTP, PIN, jeton, secret, QR sensible complet) n'apparaît
           dans les journaux, même en mode développement.
```

### Tests

```text
T-DEV-5  Porte dev active => OTP fixe accepté, aucun SMS réel émis.
T-DEV-6  OTP fixe sur un challenge expiré ou bloqué => refusé.
T-DEV-7  Journaux en mode dev => aucun OTP/PIN/jeton/secret en clair.
```

---

## 3. Ce que le mode développement n'autorise jamais (liste rouge)

### Principes

Les contrôles qui protègent la valeur et l'identité s'appliquent à l'identique en
développement et en production. Aucun n'est derrière la porte dev.

### Invariants

```text
INV-DEV-8  La porte dev ne peut garder QUE la liste blanche (§2). Aucun contrôle de la
           liste rouge ne se trouve jamais derrière un test de mode développement.
INV-DEV-9  Restent stricts en développement, sans exception :
           - confiance d'appareil (device-trust) ;
           - rôle métier ;
           - validité de session ;
           - PIN / action_code ;
           - idempotence des mutations économiques ;
           - anti-double-consommation ;
           - cloisonnement société ;
           - journal d'audit.
```

### Tests

```text
T-DEV-8   Mode dev actif + appareil pending_trust => action sensible refusée.
T-DEV-9   Mode dev actif + appareil blocked => login refusé.
T-DEV-10  Mode dev actif + mauvais rôle => refusé.
T-DEV-11  Mode dev actif + session expirée => refusé.
T-DEV-12  Mode dev actif + mauvais action_code => refusé.
T-DEV-13  Mode dev actif + idempotence manquante sur mutation économique => refusé.
T-DEV-14  Mode dev actif + QR déjà consommé => second refus.
```

---

## 4. Simulation d'états (le vrai outil de test)

### Principes

Tester les scénarios riches — multi-appareil, appareil neuf, appareil volé, numéro
recyclé — ne demande aucune relaxation. Cela demande de pouvoir fabriquer les conditions
par les chemins légitimes. Un seul mobile suffit.

### Invariants

```text
INV-DEV-10 La confiance d'un couple (utilisateur, appareil) ne s'obtient que par
           l'action d'approbation back-office, en développement comme en production.
           "Devenir trusted" n'a qu'une seule porte.
INV-DEV-11 La simulation se fait par des entrées légitimes :
           - identifiant d'appareil arbitraire envoyé par le client ;
           - état d'un couple (utilisateur, appareil) posé via les actions back-office
             réelles (approuver / bloquer / révoquer) ;
           - OTP de test pour la délivrance.
           Les contrôles s'appliquent ensuite sans aucune altération.
```

### Correspondance scénario / simulation

```text
Multi-appareil      : envoyer deux identifiants d'appareil distincts depuis le même mobile.
                      Chacun naît pending_trust, comme en production.
Appareil neuf       : effacer l'installation => nouvel identifiant => pending_trust.
Appareil volé       : bloquer le couple en back-office => login refusé.
Numéro recyclé      : même numéro, identifiant d'appareil neuf => pending_trust ;
                      l'administrateur voit un appareil neuf sur un compte existant.
Promotion / révoc.  : approuver puis approuver un autre appareil => révocation du premier.
```

### Tests

```text
T-DEV-15  Deux identifiants d'appareil depuis le même mobile => deux couples pending_trust
          indépendants ; approuver l'un n'affecte pas l'autre.
T-DEV-16  Aucune voie de test ne place un couple en trusted hors approbation back-office.
T-DEV-17  Blocage back-office d'un couple => login refusé (chemin de production).
```

---

## 5. Cohérence avec la doctrine principale

```text
DEV-GLB-1  Le mode développement est un sur-ensemble de facilités de délivrance et de
           simulation d'entrées ; il est un sous-ensemble vide de la sécurité : il ne
           retire aucun invariant de la doctrine principale.
DEV-GLB-2  Tout invariant de sécurité (sections device, session, actions sensibles,
           OTP, transverses) se teste deux fois : en production stricte et en mode
           développement actif. Le résultat de sécurité doit être identique.
DEV-GLB-3  Toute difficulté de test se résout par la simulation d'entrées (§4),
           jamais par l'ajout d'une exception à un contrôle.
```

---

## 6. Sources de configuration et settings sécurité mobile

### Principes

La classification des sources de configuration sécurité mobile est une doctrine V1.
Elle évite de mélanger trois responsabilités différentes :

```text
env/config                         = vérité de déploiement, runtime, secrets
acpec.mobile.security.setting      = politique sécurité mobile applicative auditable
ir.config_parameter                = legacy, UI non critique, fonctionnel non sensible
```

Cette section fixe la doctrine. Elle ne migre aucun paramètre existant et ne change pas
le runtime V1.

### Règles

```text
H5G-SRC-1  La classification production / développement / test vient de l'environnement
           ou de la configuration de déploiement. Elle ne dépend jamais de
           ir.config_parameter.

H5G-SRC-2  Les secrets techniques, credentials externes, tokens et clés de prestataires
           ont pour cible doctrinale env/config. Ils ne doivent pas être introduits comme
           nouveaux paramètres sécurité dans ir.config_parameter.

H5G-SRC-3  Les politiques sécurité mobile applicatives — durées token/session, PIN,
           OTP, antiflood, rate-limit, readiness applicative — relèvent de
           acpec.mobile.security.setting lorsqu'elles doivent être pilotables en base.

H5G-SRC-4  ir.config_parameter reste acceptable pour la compatibilité legacy, les
           paramètres UI non critiques et les paramètres fonctionnels non sensibles.
           Il peut servir de source de migration contrôlée vers un modèle applicatif,
           mais ne doit pas redevenir la source de vérité des politiques sensibles.

H5G-SRC-5  Les facilités dev ne peuvent être activées par un simple paramètre en base.
           Un setting legacy comme otp_dev_mode peut être détecté et signalé par
           readiness, mais ne doit pas rouvrir une relaxation runtime en production.

H5G-SRC-6  L'état SMS gateway V1 est reconnu comme legacy/historique : certains paramètres
           SMS peuvent encore être lus depuis ir.config_parameter par le runtime existant.
           Ce point est documenté comme OPEN-H5G-SMS-001 et ne doit pas être migré en V1
           sans faille majeure démontrée ou décision dédiée.
```

### Décision V1

```text
Aucun changement runtime imposé par cette doctrine.
Aucune migration SMS en V1.
Aucun changement de sms_gateway ni de res.config.settings en V1.
Les écarts non critiques restent ouverts et documentés.
```

### Critères de réouverture immédiate

Le sujet SMS/ICP doit être rouvert avant V2 uniquement si l'un des cas suivants est
démontré :

```text
- secret SMS exposé publiquement ;
- secret SMS loggé en clair ;
- utilisateur non autorisé pouvant lire ou modifier SMS_TOKEN / SMS_VALIDATION_KEY ;
- readiness production donnant un feu vert malgré secrets absents ou incohérents ;
- usage SMS permettant un bypass OTP ou une dégradation fail-open.
```
