# The languages ContentSpiel can serve (spec §4.1): ISO 639-1 code =>
# [English name, native name]. Which of these a site actually publishes is a
# runtime setting (`site_settings.locales`, read through `Locales`); this list
# only bounds what can be enabled. Plain Ruby rather than a YAML file or an
# autoloaded constant because config/application.rb needs it before any model
# loads, to hand Mobility its locale set.
SUPPORTED_LOCALES = {
  "ar" => [ "Arabic", "العربية" ], "bg" => [ "Bulgarian", "Български" ], "ca" => [ "Catalan", "Català" ],
  "cs" => [ "Czech", "Čeština" ], "da" => [ "Danish", "Dansk" ], "de" => [ "German", "Deutsch" ],
  "el" => [ "Greek", "Ελληνικά" ], "en" => [ "English", "English" ], "es" => [ "Spanish", "Español" ],
  "et" => [ "Estonian", "Eesti" ], "fi" => [ "Finnish", "Suomi" ], "fr" => [ "French", "Français" ],
  "he" => [ "Hebrew", "עברית" ], "hi" => [ "Hindi", "हिन्दी" ], "hr" => [ "Croatian", "Hrvatski" ],
  "hu" => [ "Hungarian", "Magyar" ], "id" => [ "Indonesian", "Bahasa Indonesia" ], "is" => [ "Icelandic", "Íslenska" ],
  "it" => [ "Italian", "Italiano" ], "ja" => [ "Japanese", "日本語" ], "ko" => [ "Korean", "한국어" ],
  "lt" => [ "Lithuanian", "Lietuvių" ], "lv" => [ "Latvian", "Latviešu" ], "nb" => [ "Norwegian Bokmål", "Norsk bokmål" ],
  "nl" => [ "Dutch", "Nederlands" ], "pl" => [ "Polish", "Polski" ], "pt" => [ "Portuguese", "Português" ],
  "ro" => [ "Romanian", "Română" ], "ru" => [ "Russian", "Русский" ], "sk" => [ "Slovak", "Slovenčina" ],
  "sl" => [ "Slovenian", "Slovenščina" ], "sr" => [ "Serbian", "Српски" ], "sv" => [ "Swedish", "Svenska" ],
  "th" => [ "Thai", "ไทย" ], "tr" => [ "Turkish", "Türkçe" ], "uk" => [ "Ukrainian", "Українська" ],
  "vi" => [ "Vietnamese", "Tiếng Việt" ], "zh" => [ "Chinese", "中文" ]
}.freeze
