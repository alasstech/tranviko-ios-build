# Configuration Apple et Firebase

## Faisable avant l'activation du compte Apple

1. Dans le projet Firebase `notification-push-transport`, ajouter une application iOS.
2. Utiliser exactement le Bundle ID `app.tranviko.mobile`.
3. Telecharger `GoogleService-Info.plist` et le transmettre hors Git au developpeur Mac.
4. Le placer dans `ios/Runner/GoogleService-Info.plist`.

## A faire avec le compte Apple Developer Tranviko

1. Enregistrer l'App ID explicite `app.tranviko.mobile` dans Certificates, Identifiers & Profiles.
2. Activer Push Notifications pour cet App ID.
3. Creer une cle d'authentification APNs `.p8`, conserver son Key ID et relever le Team ID. Une cle APNs Team Scoped fonctionne avec Sandbox et Production. Si le portail impose des cles Topic Specific par environnement, creer la cle associee correspondante : le backend Tranviko accepte les deux modes.
4. Limiter la cle aux topics Tranviko lorsque l'interface Apple le permet. Le topic VoIP utilise par le backend est `app.tranviko.mobile.voip` et le topic des notifications ordinaires est `app.tranviko.mobile`.
5. Dans Firebase > Parametres du projet > Cloud Messaging, televerser la cle APNs pour l'application iOS Tranviko afin que FCM distribue aussi les notifications ordinaires sur iPhone.
6. Inviter le developpeur Mac dans l'equipe Apple/App Store Connect. Ne pas partager le mot de passe du proprietaire.
7. Dans Xcode, choisir cette equipe et laisser Automatically manage signing actif.
8. Verifier Push Notifications et Background Modes : Background fetch, Remote notifications, Voice over IP et Location updates.

## Appels natifs

Les appels quand l'application est ouverte utilisent LiveKit et CallKit. Pour l'etat termine, Tranviko implemente aussi :

- un jeton PushKit VoIP enregistre par appareil ;
- un endpoint backend dedie a ces jetons ;
- un envoi APNs avec `apns-push-type: voip`, le topic `app.tranviko.mobile.voip` et une expiration tres courte ;
- un signalement immediat de chaque push VoIP a CallKit.

La couche iOS enregistre le jeton PushKit dans le backend authentifie. Le backend signe ensuite ses requetes APNs VoIP avec la cle Apple conservee uniquement sur le VPS. Il evite le doublon FCM/PushKit appareil par appareil. Le deploiement de la cle et le test sur deux vrais iPhone restent obligatoires avant publication. Un push FCM standard ne remplace pas ce canal lorsque l'application est forcee a quitter.

La cle `.p8` va uniquement sur le VPS et dans Firebase. Le developpeur Mac n'en a pas besoin pour signer ou compiler l'IPA.

## Controle avant TestFlight

- notification visible app ouverte, en arriere-plan et verrouillee ;
- appel audio et video dans les memes etats ;
- acceptation/refus depuis CallKit ;
- micro, haut-parleur, Bluetooth et camera ;
- reconnexion LiveKit apres changement Wi-Fi/4G ;
- aucune cle privee dans le depot ;
- fiche Confidentialite et declarations des donnees coherentes avec les permissions.
