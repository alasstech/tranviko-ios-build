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

1. Lire `GUIDE_COMPLET_IOS.md` avant de modifier Xcode.
2. Verifier l'integrite du clone avec `shasum -a 256 -c SOURCE_MANIFEST.sha256`.
3. Lancer `flutter doctor -v` et corriger les erreurs iOS.
4. Placer le fichier Firebase iOS dans `ios/Runner/GoogleService-Info.plist`.
5. Lancer `./scripts/verify_ios_setup.sh`.
6. Ouvrir `ios/Runner.xcworkspace`, selectionner Runner, puis l'equipe Apple Tranviko dans Signing & Capabilities.
7. Tester sur deux vrais iPhone les notifications, CallKit, la camera, le micro, la localisation et LiveKit.

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

L'IPA est generee dans `build/ios/ipa/`. Les symboles d'obfuscation restent dans `build/symbols/ios/<numero-build>/` et doivent etre archives par Tranviko.

Ne jamais envoyer dans Git une cle `.p8`, `.p12`, un profil `.mobileprovision`, un mot de passe, une cle LiveKit serveur ou un compte de service Firebase.

Voir surtout `GUIDE_COMPLET_IOS.md`, puis `APPLE_FIREBASE_SETUP.md` pour le resume Apple/Firebase.

## Acces au depot prive

Le proprietaire ouvre le depot GitHub, puis `Settings > Collaborators and teams > Add people` et invite le nom d'utilisateur GitHub du developpeur Mac. Le developpeur accepte l'invitation recue par email ou dans GitHub, puis clone normalement le depot :

```bash
git clone https://github.com/alasstech/tranviko-ios-build.git
```

Ne partagez ni votre mot de passe GitHub, ni un Personal Access Token, ni la cle Apple `.p8`. L'acces du collaborateur pourra etre retire apres la compilation.
