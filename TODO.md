# Timi — suivi du projet

Dernière mise à jour : 2026-10-02

## Terminé

- [x] Créer l'application native macOS SwiftUI/AppKit sans dépendance externe.
- [x] Afficher Timi dans un `NSPanel` transparent, sans barre de titre et non activant.
- [x] Aligner le visage sur la référence : écran noir, yeux verticaux et sourire courbe lumineux.
- [x] Ajouter les huit ancrages autour de l'écran qui contient Timi.
- [x] Respecter la zone utilisable hors Dock et barre des menus.
- [x] Ajouter les réglages macOS natifs avec déplacement immédiat.
- [x] Mémoriser l'ancrage avec `UserDefaults`.
- [x] Ajouter le clignement, la respiration et la réaction au survol.
- [x] Ajouter le déplacement manuel natif à la souris.
- [x] Mémoriser l'offset manuel relativement à l'ancrage.
- [x] Contraindre le déplacement manuel aux limites de l'écran complet.
- [x] Ajouter l'action **Reset Offset**.
- [x] Ajouter les tests unitaires du positionnement, des offsets et des limites d'écran.
- [x] Documenter l'architecture et les décisions macOS.
- [x] Ajouter une petite réaction au clic sans voler le focus.
- [x] Ajouter un réglage persistant pour afficher ou masquer Timi.
- [x] Respecter « Réduire les animations » de macOS pour les mouvements décoratifs.
- [x] Tester la restauration et la persistance de l'état applicatif.
- [x] Exposer la réaction de Timi comme action VoiceOver.
- [x] Permettre le snap de Timi sur les quatre bords et dans les coins de l'écran.
- [x] Autoriser Timi à passer devant la barre des menus et le Dock.
- [x] Tester le calcul pur du snap, y compris le bord supérieur hors `visibleFrame`.

## Bugs connus différés

- [ ] L'icône reste vide lors d'un lancement normal avec `⌘R`, malgré sa présence dans le bundle.
- [ ] Le placement sur un écran secondaire ne survit pas correctement à un nouveau `⌘R`.

## À valider manuellement

- [ ] Confirmer que le nouveau drag natif reste exactement sous le curseur lors de mouvements rapides.
- [ ] Confirmer que la respiration est visible mais reste agréable sur une longue durée.
- [ ] Comparer le nouveau visage à la référence à taille réelle sur un écran Retina.
- [ ] Vérifier le padding, l'ombre et la lisibilité de l'icône dans le Dock et le Finder aux petites tailles.
- [ ] Confirmer que le clic déclenche la réaction sans gêner le début d'un drag.
- [ ] Vérifier la persistance après `⌘Q` puis relance pour chaque type de placement.
- [ ] Vérifier le comportement sur plusieurs Spaces et avec une application en plein écran.
- [ ] Vérifier le repositionnement après changement de résolution ou branchement d'un écran.
- [ ] Confirmer plusieurs drags successifs après avoir déplacé Timi vers un écran secondaire.
- [ ] Vérifier le snap sur les quatre bords et dans les quatre coins, sur chaque écran.
- [ ] Confirmer que Timi recouvre bien la barre des menus et le Dock sans voler le focus.

## Prochaines étapes proposées

- [ ] Ajuster le drag et la respiration selon le retour de validation manuelle.
- [ ] Ajuster précisément les proportions du visage après validation à taille réelle.
- [ ] Finaliser l'icône d'application après identification du problème du lancement Debug.
- [ ] Remplacer `com.example.Timi` par l'identifiant définitif avant distribution.
- [ ] Préparer signature, sandbox, hardened runtime et notarisation avant une release publique.

## Hors périmètre actuel

- IA, chat, voix, capture d'écran ou intégrations agent.
- Réseau, comptes, analytics ou infrastructure cloud.
- Gestion avancée de plusieurs écrans.
- Launch at login, mises à jour automatiques et distribution publique.
