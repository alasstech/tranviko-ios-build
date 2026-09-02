import 'package:uuid/uuid.dart';

const Uuid _callUuid = Uuid();

/// CallKit only accepts UUID-shaped identifiers. Use the same identifier for
/// signalling, LiveKit and the native call surface on every platform.
String newCallId() => _callUuid.v4();

bool isCallUuid(String value) => Uuid.isValidUUID(fromString: value);
