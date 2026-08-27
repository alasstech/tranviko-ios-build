# Tranviko iOS - paquet de compilation

Ce depot contient uniquement l'application Flutter partagee, sa cible iOS et les assets requis. Il ne contient ni backend, ni Android, ni base de donnees, ni cle privee.

## Prerequis Mac

- macOS avec une version recente de Xcode
- Flutter stable correspondant au projet
- CocoaPods
- un compte Apple Developer membre de l'equipe Tranviko pour signer une IPA
- `ios/Runner/GoogleService-Info.plist` fourni separement
- un jeton public Mapbox transmis separement

## Premier lancement

1. Lancer `flutter doctor -v` et corriger les erreurs iOS.
2. Placer le fichier Firebase iOS dans `ios/Runner/GoogleService-Info.plist`.
3. Lancer `./scripts/verify_ios_setup.sh`.
4. Ouvrir `ios/Runner.xcworkspace`, selectionner la cible Runner, puis l'equipe Apple Tranviko dans Signing & Capabilities.
5. Verifier les capacites Push Notifications et Background Modes.
6. Tester sur un iPhone reel les notifications, CallKit, la camera, le micro, la localisation et LiveKit.

## Compilation sans signature

Utile avant que le compte Apple Tranviko soit actif :

```bash
export MAPBOX_ACCESS_TOKEN='pk...'
BUILD_UNSIGNED=1 ./scripts/build_ipa.sh
```

Cette commande valide le code iOS mais ne produit pas une IPA distribuable.

## IPA signee

```bash
export MAPBOX_ACCESS_TOKEN='pk...'
./scripts/build_ipa.sh
```

L'IPA est generee dans `build/ios/ipa/`. Les symboles d'obfuscation restent dans `build/symbols/ios/78/` et doivent etre archives par Tranviko.

Ne jamais envoyer dans Git une cle `.p8`, `.p12`, un profil `.mobileprovision`, un mot de passe, une cle LiveKit serveur ou un compte de service Firebase.

Voir aussi `APPLE_FIREBASE_SETUP.md`.
