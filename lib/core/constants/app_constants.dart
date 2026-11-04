class AppConstants {
  static const String appName = 'OFFMAS';
  static const String appTagline = 'Off-Grid Mesh Messenger';
  static const String appVersion = '1.1.0';

  // Service ID for Nearby Connections
  static const String serviceId = 'id.offmas.messenger';

  // Packet Types
  static const String packetTypeChat = 'CHAT';
  static const String packetTypeGroupChat = 'GROUP_CHAT';
  static const String packetTypeDeliveryAck = 'DELIVERY_ACK';
  static const String packetTypeReadAck = 'READ_ACK';
  static const String packetTypeSos = 'SOS';
  static const String packetTypeProfileSync = 'PROFILE_SYNC';

  // Message Status
  static const String statusSending = 'SENDING';
  static const String statusSent = 'SENT';
  static const String statusDelivered = 'DELIVERED';
  static const String statusRead = 'READ';

  // Shared Preferences Keys
  static const String prefDisplayName = 'pref_display_name';
  static const String prefBio = 'pref_bio';
  static const String prefRole = 'pref_role';
  static const String prefNodeId = 'pref_node_id';
  static const String prefPublicKey = 'pref_public_key';
  static const String prefPrivateKey = 'pref_private_key';
}
