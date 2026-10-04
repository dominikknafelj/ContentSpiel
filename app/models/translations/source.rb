module Translations
  # One `translation_sources` entry (`Translations::Tracker`): what a
  # translation was saved against. Two shapes exist side by side:
  #
  # * the old one, a bare digest String -- everything saved before the
  #   design pass. It still answers "current or outdated" but has no text and
  #   no time, so there is nothing to diff against;
  # * the new one, `{ "digest" =>, "text" =>, "saved_at" =>, "from" => }` (`from` is the primary locale the text was in) -- the text is
  #   what the diff compares the original's current value to.
  #
  # Both stay valid forever (no data migration): every reader goes through
  # `Source.wrap`, so a record holding both shapes never raises.
  Source = Data.define(:digest, :text, :saved_at, :from) do
    # nil for nothing usable stored; never raises on junk.
    def self.wrap(entry)
      case entry
      when String then entry.empty? ? nil : new(entry, nil, nil, nil)
      when Hash
        digest = entry["digest"]
        return nil unless digest.is_a?(String) && digest.present?

        text = entry["text"]
        text = nil unless text.is_a?(String) || (text.is_a?(Array) && text.all?(String))
        from = entry["from"]
        new(digest, text, parse_time(entry["saved_at"]), from.is_a?(String) ? from : nil)
      end
    end

    def self.parse_time(value)
      value.is_a?(String) ? Time.iso8601(value) : nil
    rescue ArgumentError
      nil
    end

    def stored_text? = !text.nil?

    # True only when the stored text can be diffed against the original as
    # it reads now: it has text AND that text was in the site's current
    # primary language. After the default language changes, the stored text
    # is in the OLD one and must never be word-diffed against the new one.
    # An old entry (no `from`) is never comparable.
    def comparable? = stored_text? && from == Translations.primary_locale
  end
end
