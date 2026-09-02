# Tranviko iOS - guide complet de compilation et publication

Ce guide est la procedure de reference pour le proprietaire Tranviko et le developpeur qui compile sur Mac. Le Bundle ID est **exactement** `app.tranviko.mobile`. Ne jamais en creer un second avec une orthographe differente.

## 1. Ce qui est deja implemente dans le code

- cible Flutter iOS et projet Xcode ;
- Bundle ID `app.tranviko.mobile` ;
- descriptions iOS pour camera, micro, photos, contacts, Bluetooth, Face ID et localisation ;
- entitlement APNs avec environnement Development/Production selon le build ;
- Background Modes pour notification distante, VoIP, fetch et suivi conducteur ;
- reception PushKit dans `ios/Runner/AppDelegate.swift` ;
- affichage immediat de l'appel entrant avec CallKit ;
- enregistrement du jeton PushKit dans le backend apres authentification ;
- appels audio/video LiveKit et reprise apres acceptation native ;
- identifiants d'appel UUID compatibles CallKit sur mobile et WebAdmin ;
- protection multi-appareils : un seul appareil peut accepter un appel ;
- notifications ordinaires Firebase Messaging ;
- script de verification et script de build IPA.

Le developpeur Mac ne doit donc pas reecrire CallKit. Il doit signer, fournir Firebase, verifier les capacites et effectuer les tests reels. Le backend APNs doit etre configure separement par le proprietaire Tranviko.

## 2. Repartition des responsabilites

### Proprietaire Tranviko

1. Maintenir l'abonnement Apple Developer actif.
2. Creer l'App ID, l'app App Store Connect et la cle APNs.
3. Ajouter l'app iOS dans Firebase.
4. Inviter le developpeur Mac sur GitHub et dans App Store Connect.
5. Installer la cle APNs sur le VPS, jamais dans GitHub.
6. Conserver les archives IPA/dSYM et les symboles Flutter.

### Developpeur Mac

1. Cloner uniquement ce depot prive.
2. Installer Flutter, Xcode et CocoaPods.
3. Ajouter localement `GoogleService-Info.plist`.
4. Selectionner l'equipe Tranviko dans Xcode.
5. Compiler et tester sur deux vrais iPhone.
6. Envoyer l'archive vers TestFlight lorsque Tranviko l'autorise.

## 3. Donner acces au depot GitHub prive

Dans GitHub, le proprietaire ouvre le depot `tranviko-ios-build`, puis :

1. `Settings` > `Collaborators and teams` > `Add people`.
2. Saisir le nom d'utilisateur GitHub exact du developpeur.
3. Donner Write seulement s'il doit renvoyer des corrections. Read suffit pour une compilation sans modification.
4. Le developpeur accepte l'invitation GitHub.
5. Il clone le depot avec HTTPS ou sa cle SSH :

```bash
git clone https://github.com/alasstech/tranviko-ios-build.git
cd tranviko-ios-build
```

Ne jamais lui donner le mot de passe GitHub du proprietaire. Retirer son acces apres la mission si necessaire.

## 4. Configuration Apple Developer par le proprietaire

### 4.1 App ID

Dans `developer.apple.com/account` > Certificates, Identifiers & Profiles :

1. Ouvrir `Identifiers` et ajouter un App ID de type App.
2. Description : `Tranviko`.
3. Bundle ID explicite : `app.tranviko.mobile`.
4. Activer `Push Notifications`.
5. Enregistrer.

### 4.2 App Store Connect

Dans `appstoreconnect.apple.com` > My Apps :

1. Ajouter une nouvelle app iOS.
2. Nom : `Tranviko`.
3. Bundle ID : `app.tranviko.mobile`.
4. SKU interne : par exemple `TRANVIKO-IOS-001`.
5. Langue principale : Francais.

### 4.3 Inviter le developpeur Mac

Dans App Store Connect > Users and Access :

1. Ajouter son adresse Apple ID.
2. Role minimal recommande : Developer.
3. Limiter son acces a l'app Tranviko.
4. Activer l'acces Certificates, Identifiers & Profiles seulement s'il doit regler la signature.

Le compte Account Holder reste sous le controle exclusif de Tranviko.

Si le compte Apple Developer est inscrit comme **organisation**, un utilisateur
Developer peut recevoir l'acces aux certificats et profils selon les droits
accordes. Si le compte est inscrit comme **individu**, les personnes ajoutees
dans App Store Connect ne deviennent pas automatiquement membres de l'equipe
Apple Developer. Dans ce cas, ne partagez jamais le compte du proprietaire : le
developpeur peut preparer le projet, mais la signature doit suivre la procedure
manuelle ci-dessous ou etre effectuee par le proprietaire.

### 4.4 Signature si le compte est individuel

Le mot de passe Apple du proprietaire ne doit jamais etre communique. Utiliser
plutot cette procedure :

1. Sur le Mac, le developpeur ouvre Trousseaux d'acces > Assistant de
   certification > Demander un certificat a une autorite de certification.
2. Il enregistre le fichier CSR et transmet uniquement ce CSR au proprietaire.
3. Pour tester sur iPhone, il transmet aussi les UDID des deux appareils.
4. Le proprietaire cree dans le portail Apple un certificat Apple Development
   avec ce CSR, enregistre les iPhone, puis cree un profil iOS App Development
   pour `app.tranviko.mobile` avec Push Notifications.
5. Pour TestFlight, le proprietaire cree aussi un certificat Apple Distribution
   avec le CSR et un profil App Store Connect pour le meme Bundle ID.
6. Les fichiers `.cer` et `.mobileprovision` sont transmis par un canal prive,
   jamais par GitHub, email public ou messagerie non chiffree.
7. Le developpeur installe les certificats/profils, choisit la signature manuelle
   dans Xcode et verifie les entitlements de l'archive avant l'upload.
8. Le proprietaire invite tout de meme son Apple Account avec le role Developer
   limite a Tranviko afin qu'il puisse televerser le build dans App Store Connect.

La cle privee creee avec le CSR reste dans le trousseau du Mac. A la fin de la
mission, le proprietaire peut revoquer les certificats et retirer les acces sans
revoquer la cle APNs du serveur.

## 5. Creer la cle APNs `.p8`

Cette operation exige le role Account Holder ou Admin.

1. Ouvrir Certificates, Identifiers & Profiles > Keys.
2. Cliquer `+` et nommer la cle `Tranviko APNs`.
3. Cocher Apple Push Notification service (APNs), puis Configure.
4. Preferer une cle Topic Specific limitee aux topics Tranviko si Apple propose ce choix. Sinon utiliser Team Scoped.
5. Confirmer et telecharger le fichier `AuthKey_<KEY_ID>.p8`.
6. Noter le Key ID affiche sur la fiche de la cle.
7. Relever le Team ID dans Membership details.

Le fichier `.p8` ne peut etre telecharge qu'une fois. Le conserver dans un coffre de secrets chiffre. Une cle APNs Team Scoped fonctionne sur les serveurs APNs Development et Production. Si Apple fournit des cles Topic Specific separees par environnement, utiliser la configuration alternative de la section 11.

## 6. Ajouter Firebase iOS

Dans le projet Firebase utilise par Tranviko :

1. Parametres du projet > Vos applications > Ajouter une app iOS.
2. Bundle ID : `app.tranviko.mobile`.
3. Nom facultatif : `Tranviko iOS`.
4. Telecharger `GoogleService-Info.plist`.
5. Dans Cloud Messaging, televerser la cle APNs `.p8`, son Key ID et le Team ID pour l'app iOS.
6. Transmettre `GoogleService-Info.plist` au developpeur par un canal prive.

`GoogleService-Info.plist` doit etre place dans `ios/Runner/GoogleService-Info.plist`. Il est ignore par Git volontairement. La cle APNs `.p8` ne doit jamais etre transmise au developpeur Mac et ne doit jamais entrer dans ce depot.

## 7. Preparer le Mac

```bash
xcode-select --install
sudo xcodebuild -license accept
flutter doctor -v
brew install cocoapods
pod --version
```

Si Homebrew n'est pas installe, CocoaPods peut aussi etre installe avec Ruby,
mais Homebrew evite la plupart des conflits avec le Ruby systeme de macOS.

Utiliser une version Flutter stable compatible avec `pubspec.lock`. Corriger toutes les lignes rouges de `flutter doctor -v` concernant Xcode avant de continuer.

Puis, depuis le depot :

```bash
flutter clean
flutter pub get
cd ios
pod install --repo-update
cd ..
chmod +x scripts/*.sh
./scripts/verify_ios_setup.sh
```

Toujours ouvrir `ios/Runner.xcworkspace`, jamais `Runner.xcodeproj` apres l'installation CocoaPods.

## 8. Signing & Capabilities dans Xcode

Dans Xcode :

1. Ouvrir `ios/Runner.xcworkspace`.
2. Selectionner le projet Runner puis la cible Runner.
3. `Signing & Capabilities` > cocher Automatically manage signing.
4. Selectionner l'equipe Apple Developer Tranviko.
5. Verifier que le Bundle Identifier reste `app.tranviko.mobile`.
6. Verifier la capacite `Push Notifications`.
7. Verifier `Background Modes` avec Background fetch, Remote notifications, Voice over IP et Location updates.
8. Verifier que `GoogleService-Info.plist` apparait dans Runner et a Target Membership `Runner`.

Xcode doit generer un provisioning profile contenant l'entitlement APNs. En Debug, `aps-environment` vaut development. En Archive/TestFlight/App Store, il vaut production.

## 9. Premier build et tests locaux

Brancher un vrai iPhone, lui faire confiance et choisir cet iPhone comme destination Xcode. Un simulateur ne valide pas PushKit/APNs, la camera, le routage audio ou CallKit verrouille.

```bash
export MAPBOX_ACCESS_TOKEN='pk...'
flutter run --release \
  --dart-define=API_BASE_URL=https://tranviko.app/api \
  --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN"
```

Faire au minimum un lancement Debug depuis Xcode pour obtenir un jeton APNs Sandbox, puis un build TestFlight pour verifier APNs Production.

## 10. Generer l'IPA

Validation sans signature :

```bash
export MAPBOX_ACCESS_TOKEN='pk...'
BUILD_UNSIGNED=1 ./scripts/build_ipa.sh
```

IPA signee :

```bash
export MAPBOX_ACCESS_TOKEN='pk...'
./scripts/build_ipa.sh
```

Le resultat se trouve dans `build/ios/ipa/`. Les symboles d'obfuscation se trouvent dans `build/symbols/ios/<numero-build>/`. Conserver aussi les dSYM de l'archive Xcode pour diagnostiquer les crashs.

Si un `ExportOptions.plist` approuve par Tranviko est fourni :

```bash
export EXPORT_OPTIONS_PLIST='/chemin/ExportOptions.plist'
./scripts/build_ipa.sh
```

Pour TestFlight, utiliser Xcode Organizer > Distribute App > App Store Connect > Upload, ou l'app Transporter. Ne publier en production qu'apres validation TestFlight sur deux iPhone.

## 11. Configurer APNs VoIP sur le VPS

### Mode recommande : une cle APNs commune

Copier la cle hors du depot :

```bash
sudo install -d -m 700 /opt/tranviko/secrets
sudo install -m 600 ~/AuthKey_XXXXXXXXXX.p8 /opt/tranviko/secrets/AuthKey_Tranviko_APNs.p8
cp deploy/docker-compose.apns.yml.example deploy/docker-compose.apns.yml
```

Dans `.env.production` :

```dotenv
APPLE_VOIP_ENABLED=true
APPLE_VOIP_BUNDLE_ID=app.tranviko.mobile
APPLE_APNS_TEAM_ID=VOTRE_TEAM_ID
APPLE_APNS_KEY_ID=VOTRE_KEY_ID
APPLE_APNS_PRIVATE_KEY_PATH=/run/secrets/apple-apns-key.p8
APPLE_APNS_TIMEOUT=8
```

Laisser les variables `APPLE_APNS_DEVELOPMENT_*` et `APPLE_APNS_PRODUCTION_*` vides.

### Mode alternatif : cles distinctes

Si Apple a cree une cle Development et sa Related Key Production, monter les deux fichiers et remplir :

```dotenv
APPLE_APNS_DEVELOPMENT_KEY_ID=KEY_DEV
APPLE_APNS_DEVELOPMENT_PRIVATE_KEY_PATH=/run/secrets/apple-apns-development-key.p8
APPLE_APNS_PRODUCTION_KEY_ID=KEY_PROD
APPLE_APNS_PRODUCTION_PRIVATE_KEY_PATH=/run/secrets/apple-apns-production-key.p8
```

Adapter alors `deploy/docker-compose.apns.yml` pour monter les deux chemins. Ne pas melanger un jeton Sandbox avec `api.push.apple.com`, ni un jeton Production avec `api.sandbox.push.apple.com`.

Deployer :

```bash
docker compose --env-file .env.production \
  -f docker-compose.production.yml \
  -f deploy/docker-compose.apns.yml \
  up -d --build backend

docker compose --env-file .env.production \
  -f docker-compose.production.yml \
  -f deploy/docker-compose.apns.yml \
  exec backend python manage.py migrate
```

Verifier sans afficher la cle :

```bash
docker compose --env-file .env.production \
  -f docker-compose.production.yml \
  -f deploy/docker-compose.apns.yml \
  exec backend test -r /run/secrets/apple-apns-key.p8

docker compose --env-file .env.production \
  -f docker-compose.production.yml \
  -f deploy/docker-compose.apns.yml \
  exec backend python manage.py shell -c "from transport.push_services import _apple_provider_token; print(len(_apple_provider_token('production')) > 100)"

docker compose --env-file .env.production \
  -f docker-compose.production.yml \
  -f deploy/docker-compose.apns.yml \
  exec backend python manage.py shell -c "from transport.models import AppleVoipDevice; print(list(AppleVoipDevice.all_objects.values('environment','device_name','is_active','last_success_at','last_error')))"
```

Le deuxieme controle doit afficher `True`. La liste des appareils n'apparait qu'apres connexion reelle sur iPhone et enregistrement du jeton PushKit.

## 12. Fonctionnement de PushKit, CallKit et LiveKit

1. iOS attribue un jeton PushKit unique a l'installation.
2. Apres connexion, Tranviko envoie ce jeton au backend authentifie avec l'identifiant de l'appareil et l'environnement.
3. Lors d'un appel, le backend envoie un push VoIP APNs de courte duree avec le topic `app.tranviko.mobile.voip`.
4. iOS lance ou reveille l'app et appelle `AppDelegate.pushRegistry`.
5. L'app signale immediatement l'appel a CallKit, comme l'exige Apple.
6. Quand l'utilisateur accepte, le backend attribue atomiquement l'appel a cet appareil. Les autres appareils du meme compte sont fermes.
7. L'app recupere ensuite son jeton LiveKit et joint la salle audio/video.
8. Les jetons APNs invalides sont desactives automatiquement par le backend.

PushKit sert uniquement aux invitations d'appel. Les messages, stories et notifications ordinaires restent sur FCM/APNs standard. Ne jamais utiliser un push VoIP pour du marketing ou un simple message.

## 13. Matrice de tests obligatoire sur deux iPhone

Executer chaque ligne en audio puis en video :

| Emetteur | Recepteur | Etat recepteur | Resultat attendu |
|---|---|---|---|
| iPhone A | iPhone B | app ouverte | CallKit, acceptation, son bidirectionnel |
| iPhone A | iPhone B | app en arriere-plan | CallKit, retour a l'appel, son/video |
| iPhone A | iPhone B | ecran verrouille | CallKit sur ecran verrouille, deverrouillage sans coupure |
| iPhone A | iPhone B | processus non actif | reveil par PushKit et CallKit |
| iPhone A | deux appareils du meme compte | les deux sonnent | un seul accepte, l'autre affiche appel pris ailleurs |
| Wi-Fi | 4G/5G | changement de reseau pendant appel | reconnexion LiveKit sans double appel |

Verifier aussi : micro, haut-parleur, ecouteur, Bluetooth, camera avant/arriere, camera coupee, refus, appel manque, raccrochage des deux cotes et absence de deuxieme icone Tranviko dans le multitache.

Un arret force manuel par l'utilisateur peut etre traite differemment par iOS selon la version. Il faut tester le build TestFlight exact; ne jamais promettre un comportement que le systeme Apple peut volontairement bloquer.

## 14. Diagnostic rapide

### L'appel ne s'affiche pas

- verifier que l'iPhone a ouvert et authentifie l'app au moins une fois ;
- verifier `AppleVoipDevice` dans le backend ;
- verifier Sandbox pour Debug et Production pour TestFlight ;
- verifier le topic `app.tranviko.mobile.voip` ;
- verifier Push Notifications et le provisioning profile ;
- lire `last_error` : `BadDeviceToken`, `DeviceTokenNotForTopic`, `InvalidProviderToken` ou `Unregistered` donnent la cause APNs.

### CallKit s'affiche mais l'appel ne se connecte pas

- verifier WebSocket et LiveKit ;
- verifier UDP `50000-50100` et TCP `7881` sur le VPS ;
- verifier `LIVEKIT_WS_URL=wss://livekit.tranviko.app` ;
- verifier que les deux appareils utilisent le meme `callId` UUID.

### Notification ordinaire absente

- verifier Firebase Cloud Messaging et la cle APNs chargee dans Firebase ;
- verifier l'autorisation Notifications iOS ;
- verifier le jeton `PushDevice`, distinct du jeton `AppleVoipDevice`.

## 15. Regles de securite

- jamais de `.p8`, `.p12`, `.mobileprovision`, mot de passe ou secret LiveKit dans Git ;
- jamais de cle APNs dans Flutter ou sur le Mac d'un prestataire ;
- ne transmettre que le jeton public Mapbox au build ;
- revoquer immediatement une cle APNs exposee et en creer une nouvelle ;
- retirer les acces GitHub/App Store Connect inutiles apres livraison ;
- conserver les symboles de crash dans un stockage Tranviko prive.

## 16. References officielles

- PushKit et signalement CallKit : https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit
- Creation d'une cle APNs : https://developer.apple.com/help/account/keys/create-a-private-key
- Authentification APNs par jeton : https://developer.apple.com/help/account/capabilities/communicate-with-apns-using-authentication-tokens/
- Build IPA Flutter : https://docs.flutter.dev/deployment/ios
- Upload App Store Connect : https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- Comptes individuels et acces App Store Connect : https://developer.apple.com/help/app-store-connect/manage-your-team/add-and-edit-users/
- Roles Apple Developer : https://developer.apple.com/help/account/access/roles
- Firebase pour Apple : https://firebase.google.com/docs/cloud-messaging/ios/get-started
