# Timi — suivi du projet

Dernière mise à jour : 2026-10-05

## Terminé

- [x] Mises à jour automatiques via Sparkle 2 (menu, Réglages, scripts de release, documentation) ; en attente de validation manuelle.
- [x] Ajouter l’auto-hide (Désactivé / Masquer complètement / 4 pt visibles) avec délai réglable en secondes : Timi glisse contre le bord le plus proche sans écran voisin et réapparaît au survol du bord.
- [x] Ajouter l’icône de barre des menus (`NSStatusItem`, icône template) avec Afficher/Masquer, Réglages et Quitter.
- [x] Refaire l’icône d’app avec les deux yeux capsules de face aux proportions de `EyeProjection`.
- [x] Ajouter la dictée globale locale avec raccourci hybride configurable et `CGEventTap`.
- [x] Permettre au raccourci de fonctionner en écoute seule avant l’autorisation Accessibilité, puis réinstaller automatiquement le tap neutralisant.
- [x] Fiabiliser le raccourci avec l’enregistrement système macOS, afficher son état réel et proposer un test direct dans Réglages, avec `CGEventTap` en repli.
- [x] Ne plus interrompre chaque dictée globale avec la demande Accessibilité ; conserver le repli presse-papiers et la demande explicite dans Réglages.
- [x] Partager un `DictationCoordinator` entre la conversation et la dictée globale.
- [x] Afficher dans la tête les états écoute, silence, finalisation, nettoyage, insertion, succès et erreur.
- [x] Piloter une onde à neuf barres par le RMS réel, lissée et limitée à 20 Hz, sans conserver l’audio.
- [x] Détecter trois secondes de silence et 1,5 seconde sans buffer microphone.
- [x] Finaliser réellement `SpeechAnalyzer` avant de terminer la tâche de résultats.
- [x] Demander alternatives et confiance et injecter jusqu’à 200 termes via `AnalysisContext`.
- [x] Nettoyer avec une session Apple Intelligence indépendante, validation de sortie, timeout et repli conservateur.
- [x] Insérer au focus courant par collage natif AX, avec repli presse-papiers et exclusion des champs sécurisés.
- [x] Ajouter le catalogue JSON atomique de vocabulaire, corrections et historique limité à 100 entrées / 30 jours.
- [x] Ajouter les réglages Raccourci, Nettoyage, Vocabulaire et Historique et la correction confirmée.
- [x] Ajouter les annonces VoiceOver et une variante d’onde pour Réduire les animations.
- [x] Tester RMS, lissage, nettoyage, raccourci hybride, rétention, corruption et persistance du catalogue.

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
- [x] Valider le drag rapide, le clic et plusieurs drags successifs.
- [x] Faire affleurer la forme noire au bord de l'écran sans marge transparente.
- [x] Remplacer les yeux verticaux par des yeux ronds et conserver l'écart avec le sourire.
- [x] Remplacer le visage par deux yeux allongés sans bouche, projetés sur une sphère avec perspective latérale.
- [x] Supprimer l'ombre extérieure coupée par les limites du `NSPanel`.
- [x] Remplacer l'icône illustrée par une tête carrée simple sans ombre.
- [x] Contraindre la tête visible à l'écran pendant le drag, et pas seulement au relâchement.
- [x] Confirmer l'affichage de l'icône lors d'un lancement normal avec `⌘R`.
- [x] Confirmer la restauration du placement sur un écran secondaire après relance.
- [x] Ouvrir une bulle de conversation native au clic sur Timi.
- [x] Intégrer le modèle local Apple Intelligence avec `FoundationModels` sur macOS 26 et versions ultérieures.
- [x] Afficher la réponse progressivement et conserver le contexte de la conversation pendant la session.
- [x] Transformer le bouton haut-parleur en bascule muet : coupe la lecture en cours immédiatement et empêche les lectures suivantes tant qu’il est actif (non persisté).
- [x] Expliquer les états indisponible, désactivé, incompatible et modèle en préparation.
- [x] Conserver la cible macOS 14 avec une activation conditionnelle de la conversation intelligente.
- [x] Positionner la bulle dans la zone visible à côté de Timi avec un calcul pur testé.
- [x] Garder le champ de question éditable lorsque Apple Intelligence est indisponible et expliquer son état.
- [x] Revérifier Apple Intelligence à l’envoi pour éviter un bouton bloqué après son activation dans Réglages Système.
- [x] Aligner la cible minimale sur macOS 26, Apple Intelligence étant une capacité centrale de Timi.
- [x] Ajouter un bouton de dictée avec transcription locale progressive via `SpeechTranscriber`.
- [x] Utiliser `DictationTranscriber` comme repli local lorsque le nouveau modèle vocal est indisponible.
- [x] Ajouter la permission microphone et l’entitlement audio du Hardened Runtime.
- [x] Finaliser la transcription à l’arrêt et couper automatiquement le microphone à la fermeture de la bulle.
- [x] Lire automatiquement chaque réponse complète avec la meilleure voix système disponible pour sa langue.
- [x] Ajouter dans les réglages le choix persistant et l’aperçu des voix réellement accessibles à Timi.
- [x] Isoler la préparation Core Audio hors du thread principal pour éviter le gel de l’interface au démarrage de la dictée.
- [x] Ajouter un choix persistant de langue de dictée dans les réglages, avec le français par défaut.
- [x] Ajouter un bouton dans la conversation pour interrompre immédiatement la lecture vocale de Timi.
- [x] Revenir à un Timi noir unique avec ses yeux sphériques animés, sans personnalisation de forme ou de couleur.
- [x] Retirer la bordure, les raccords et leur marge de dessin afin de retrouver le `NSPanel` simple de 148 × 104 pt.
- [x] Adapter la silhouette avec des raccords concaves extérieurs façon notch lorsque Timi est collé à un bord, y compris dans les coins.
- [x] Dimensionner le masque du contenu sur le panneau complet pour éviter de rogner les yeux et les états de dictée.
- [x] Faire suivre le curseur par les yeux (lecture de `NSEvent.mouseLocation`, sans permission), avec lissage et retour à la dérive si Timi est masqué.

## À valider manuellement

- [ ] Valider l’auto-hide : mode complet et 4 pt, deux écrans, chat ouvert, dictée globale, drag, plein écran.
- [ ] Valider l’icône de barre des menus en thème clair et sombre, et la nouvelle icône d’app à 16 pt.
- [ ] Autoriser Microphone, Reconnaissance vocale, Accessibilité et Surveillance de l’entrée sur une installation neuve.
- [ ] Valider appui bref, maintien, second appui et les trois raccourcis configurables hors de Timi.
- [ ] Vérifier le conflit `⌃ Espace` avec le changement de source de saisie macOS.
- [ ] Tester collage et restauration du presse-papiers dans TextEdit, Slack, Gmail, Xcode et un `contenteditable`.
- [ ] Vérifier les replis sans focus, en lecture seule, champ sécurisé et Secure Input actif.
- [ ] Changer volontairement de focus pendant « Je nettoie… » et confirmer la destination finale.
- [ ] Débrancher/changer le microphone et confirmer « Micro interrompu » avec le brut dans le presse-papiers.
- [ ] Valider VoiceOver et Réduire les animations pour tous les états de dictée.
- [ ] Vérifier hors ligne, modèles déjà téléchargés, qu’aucune donnée ne quitte le Mac.

- [x] Confirmer que le nouveau drag natif reste exactement sous le curseur lors de mouvements rapides.
- [ ] Confirmer que la respiration est visible mais reste agréable sur une longue durée.
- [x] Comparer le nouveau visage à la référence à taille réelle sur un écran Retina.
- [ ] Vérifier le padding, l'ombre et la lisibilité de l'icône dans le Dock et le Finder aux petites tailles.
- [x] Confirmer que le clic déclenche la réaction sans gêner le début d'un drag.
- [ ] Vérifier la persistance après `⌘Q` puis relance pour chaque type de placement.
- [ ] Vérifier le comportement sur plusieurs Spaces et avec une application en plein écran.
- [ ] Vérifier le repositionnement après changement de résolution ou branchement d'un écran.
- [x] Confirmer plusieurs drags successifs après avoir déplacé Timi vers un écran secondaire.
- [ ] Vérifier le snap contraint sur les quatre bords et dans les quatre coins, sur chaque écran.
- [x] Confirmer que Timi recouvre bien la barre des menus et reste devant les autres applications sans voler le focus.
- [ ] Vérifier le focus automatique du champ, l’envoi avec Entrée et la fermeture avec Échap.
- [ ] Vérifier visuellement la bulle lorsque Timi est placé sur chacun des quatre bords et dans les quatre coins.
- [ ] Confirmer une réponse Apple Intelligence complète en français puis une question de suivi.
- [ ] Vérifier le message de repli sur un Mac non compatible ou lorsque Apple Intelligence est désactivé.
- [ ] Accepter la permission microphone puis confirmer une dictée complète en français.
- [ ] Confirmer que l’activation du microphone ne fige plus l’interface pendant la préparation du moteur audio.
- [ ] Vérifier le texte progressif, la correction finale et la conservation du texte déjà saisi.
- [ ] Vérifier que fermer la bulle pendant une dictée coupe immédiatement le microphone.
- [ ] Tester le message d’erreur après refus de la permission microphone.
- [ ] Télécharger une voix française Premium puis confirmer sa sélection et la qualité de lecture des réponses.
- [ ] Vérifier que le bouton d'arrêt vocal s'active pendant la lecture et coupe immédiatement la réponse.
- [ ] Valider à taille réelle le mouvement sphérique des yeux de gauche à droite et leur compression en perspective.
- [ ] Valider le suivi du curseur : sens vertical, amplitude, fluidité, autre écran et autre app au premier plan ; au repos avec « Réduire les animations ».
- [ ] Confirmer à taille réelle que la silhouette noire fixe reste nette et affleure correctement chaque bord.
- [ ] Valider visuellement les raccords façon notch sur les quatre bords et dans les quatre coins.
- [ ] Confirmer que les yeux, le libellé et l’onde de dictée restent entièrement visibles pendant la respiration et le survol.

## Prochaines étapes proposées

- [ ] Sparkle : lancer `scripts/generate-keys.sh`, renseigner `SUPublicEDKey`, créer le certificat auto-signé, choisir le vrai bundle identifier, puis valider manuellement le scénario 1.0.0 → 1.0.1 (voir `RELEASING.md`).
- [ ] Ajuster la respiration selon le retour de validation manuelle.
- [ ] Finaliser l'icône d'application après validation visuelle aux petites tailles.
- [ ] Ajuster la taille et le style de la bulle après validation en usage réel.

## Hors périmètre actuel

- Capture d'écran ou intégrations agent.
- Réseau, comptes, analytics ou infrastructure cloud.
- Gestion avancée de plusieurs écrans.
- Launch at login.
- Signature de distribution, notarisation et publication sur le Mac App Store tant que le projet reste privé.
