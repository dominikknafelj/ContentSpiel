# Class strings shared by the setup wizard's views, kept in one place so the
# steps stay visually consistent. Product UI -- uses the Content·Spiel tokens.
module SetupHelper
  def setup_input_class
    "mt-1 block w-full rounded-t-field border-0 border-b border-field-line bg-field-fill px-3 py-2 text-ink focus:outline-2 focus:outline-accent"
  end

  # A native `<select>`: `.cs-select` draws the border, chevron and focus ring
  # from tokens (content-spiel.tailwind.css), so it needs no other styling.
  def setup_select_class
    "cs-select w-full"
  end

  def setup_label_class
    "block text-label text-meta"
  end

  # The wizard's buttons are links drawn as the component's buttons: the same
  # strings (`Admin::Ui::ButtonComponent.classes`), whose common classes carry
  # the `inline-flex` a link needs to be one.
  def setup_primary_button_class
    Admin::Ui::ButtonComponent.classes(:primary)
  end

  def setup_secondary_link_class
    Admin::Ui::ButtonComponent.classes(:secondary)
  end

  # "Skip" on an optional step: accent words, no fill, so Continue stays the
  # one emphasised action (the component's :tertiary).
  def setup_tertiary_link_class
    Admin::Ui::ButtonComponent.classes(:tertiary)
  end

  # The wizard's step list is "done" for every step before the current one:
  # steps are strictly ordered and each persists as it is submitted.
  def setup_step_done?(step, current)
    SetupController::STEPS.index(step) < SetupController::STEPS.index(current)
  end

  # Native name (e.g. "Deutsch" for "de") -- the setup wizard is naming
  # languages for whoever picks them, not describing them in English.
  def language_name(code)
    ::Locales.name(code, native: true)
  end

  # `<option>` pairs for every *supported* language (spec §4.1), not just the
  # ones currently enabled -- the languages step is exactly where a site
  # turns a new one on, so it has to offer the full ~40-language list rather
  # than the handful `Locales.enabled` already returns. Sorted by code, which
  # is already alphabetical in `SUPPORTED_LOCALES`.
  def language_options
    ::Locales::SUPPORTED.keys.map { |code| [ "#{language_name(code)} (#{code.upcase})", code ] }
  end
end
