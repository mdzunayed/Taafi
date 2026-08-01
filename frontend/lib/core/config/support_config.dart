/// Official Taafi brand tagline (Bangla), shown at customer touchpoints
/// such as the auth screens and web manifest.
const String kBrandTaglineBn = 'জ্যাম আর সিরিয়ালকে বিদায়, চিকিৎসা এখন আপনার দরজায়';

class SupportConfig {
  SupportConfig._();

  static const String supportPhone = '+8801700000000';
  static const String supportPhoneDisplay = '+880 1700 000 000';

  /// Official Taafi support WhatsApp line. Kept separate from [supportPhone]
  /// so the voice hotline and the chat line can diverge without touching the
  /// call sites. Consumed by `launchWhatsAppSupport`.
  static const String whatsappNumber = '+8801700000000';
  static const String whatsappNumberDisplay = '+880 1700 000 000';
  static const String supportEmail = 'support@taafi.app';
  static const String supportHoursLabel = 'Support hours · 9 AM – 9 PM (BST)';
  static const String faqAsset = 'assets/data/patient_faq.json';
}
