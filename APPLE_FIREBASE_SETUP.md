# Configuration Apple et Firebase

## Faisable avant l'activation du compte Apple

1. Dans le projet Firebase `notification-push-transport`, ajouter une application iOS.
2. Utiliser exactement le Bundle ID `app.tranviko.mobile`.
3. Telecharger `GoogleService-Info.plist` et le transmettre hors Git au developpeur Mac.
4. Le placer dans `ios/Runner/GoogleService-Info.plist`.

## A faire avec le compte Apple Developer Tranviko

1. Enregistrer l'App ID explicite `app.tranviko.mobile` dans Certificates, Identifiers & Profiles.
2. Activer Push Notifications pour cet App ID.
3. Creer une cle APNs `.p8`, conserver son Key ID et relever le Team ID. Le fichier ne se telecharge qu'une fois.
4. Dans Firebase > Parametres du projet > Cloud Messaging, televerser la cle APNs pour l'application iOS Tranviko.
5. Inviter le developpeur Mac dans l'equipe Apple/App Store Connect. Ne pas partager le mot de passe du proprietaire.
6. Dans Xcode, choisir cette equipe et laisser Automatically manage signing actif.
7. Verifier Push Notifications et Background Modes : Background fetch, Remote notifications, Voice over IP et Location updates.

## Appels natifs

Les appels quand l'application est ouverte utilisent deja LiveKit et CallKit. Les appels fiables lorsque l'application est terminee exigent en plus :

- un jeton PushKit VoIP enregistre par appareil ;
- un endpoint backend dedie a ces jetons ;
- un envoi APNs avec `apns-push-type: voip`, le topic `app.tranviko.mobile.voip` et une expiration tres courte ;
- un signalement immediat de chaque push VoIP a CallKit.

La couche iOS est preparee pour recevoir PushKit et afficher CallKit. Le raccordement serveur des jetons VoIP doit etre termine et teste sur deux iPhone reels avant publication. Un push FCM standard ne remplace pas ce canal lorsque l'application est forcee a quitter.

## Controle avant TestFlight

- notification visible app ouverte, en arriere-plan et verrouillee ;
- appel audio et video dans les memes etats ;
- acceptation/refus depuis CallKit ;
- micro, haut-parleur, Bluetooth et camera ;
- reconnexion LiveKit apres changement Wi-Fi/4G ;
- aucune cle privee dans le depot ;
- fiche Confidentialite et declarations des donnees coherentes avec les permissions.
