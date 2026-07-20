import 'package:flutter/widgets.dart';

enum MilaLanguage { ru, en, uz }

const supportedMilaLanguageNames = ['Русский', 'English', 'O\'zbekcha'];

MilaLanguage milaLanguageFromName(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'english' || normalized == 'en') return MilaLanguage.en;
  if (normalized == 'o\'zbekcha' ||
      normalized == 'ozbekcha' ||
      normalized == 'uzbek' ||
      normalized == 'uz') {
    return MilaLanguage.uz;
  }
  return MilaLanguage.ru;
}

Locale milaLocaleFromLanguageName(String value) {
  return switch (milaLanguageFromName(value)) {
    MilaLanguage.en => const Locale('en'),
    MilaLanguage.uz => const Locale('uz'),
    MilaLanguage.ru => const Locale('ru'),
  };
}

class MilaLocalizations {
  const MilaLocalizations(this.language);

  final MilaLanguage language;

  static const delegate = _MilaLocalizationsDelegate();

  static const supportedLocales = [Locale('ru'), Locale('en'), Locale('uz')];

  static MilaLocalizations of(BuildContext context) {
    return Localizations.of<MilaLocalizations>(context, MilaLocalizations) ??
        const MilaLocalizations(MilaLanguage.en);
  }

  String pick({required String ru, required String en, required String uz}) {
    return switch (language) {
      MilaLanguage.ru => ru,
      MilaLanguage.en => en,
      MilaLanguage.uz => uz,
    };
  }

  String greeting(int hour) {
    if (hour < 12) {
      return pick(ru: 'Доброе утро', en: 'Good morning', uz: 'Xayrli tong');
    }
    if (hour < 18) {
      return pick(ru: 'Добрый день', en: 'Good afternoon', uz: 'Xayrli kun');
    }
    return pick(ru: 'Добрый вечер', en: 'Good evening', uz: 'Xayrli kech');
  }

  String voiceGender(String genderName) => switch (genderName) {
    'male' => pick(ru: 'Мужской', en: 'Male', uz: 'Erkak'),
    _ => pick(ru: 'Женский', en: 'Female', uz: 'Ayol'),
  };

  String personalityTitle(String id) => switch (id) {
    'professional' => pick(
      ru: 'Профессиональная и краткая',
      en: 'Professional & brief',
      uz: 'Professional va qisqa',
    ),
    'playful' => pick(
      ru: 'Живая и энергичная',
      en: 'Playful & energetic',
      uz: 'Jonli va sergak',
    ),
    _ => pick(
      ru: 'Тёплая и дружелюбная',
      en: 'Warm & friendly',
      uz: 'Iliq va do\'stona',
    ),
  };

  String personalitySubtitle(String id) => switch (id) {
    'professional' => pick(
      ru: 'Сфокусированная, спокойная и эффективная',
      en: 'Focused, calm and efficient',
      uz: 'Diqqatli, xotirjam va samarali',
    ),
    'playful' => pick(
      ru: 'Любознательная, бодрая и поддерживающая',
      en: 'Lively, curious and encouraging',
      uz: 'Qiziquvchan, tetik va qo\'llab-quvvatlovchi',
    ),
    _ => pick(
      ru: 'Внимательная, заботливая и естественная',
      en: 'Attentive, caring and natural',
      uz: 'E\'tiborli, g\'amxo\'r va tabiiy',
    ),
  };
}

class _MilaLocalizationsDelegate
    extends LocalizationsDelegate<MilaLocalizations> {
  const _MilaLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['ru', 'en', 'uz'].contains(locale.languageCode);
  }

  @override
  Future<MilaLocalizations> load(Locale locale) async {
    final language = switch (locale.languageCode) {
      'en' => MilaLanguage.en,
      'uz' => MilaLanguage.uz,
      _ => MilaLanguage.ru,
    };
    return MilaLocalizations(language);
  }

  @override
  bool shouldReload(_MilaLocalizationsDelegate old) => false;
}

extension MilaL10nContext on BuildContext {
  MilaLocalizations get l10n => MilaLocalizations.of(this);
}
