/// Bilingual time-of-day greeting used across home screens.
({String en, String bn}) bilingualGreeting([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) return (en: 'Good morning', bn: 'শুভ সকাল');
  if (hour < 17) return (en: 'Good afternoon', bn: 'শুভ অপরাহ্ন');
  return (en: 'Good evening', bn: 'শুভ সন্ধ্যা');
}
