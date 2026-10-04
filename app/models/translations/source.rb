module Translations
  # One `translation_sources` entry (`Translations::Tracker`): what a
  # translation was saved against. Two shapes exist side by side:
  #
  # * the old one, a bare digest String -- everything saved before the
  #   design pass. It still answers "current or outdated" but has no text and
  #   no time, so there is nothing to diff against;
  # * the new one, `{ "digest" =>, "text" =>, "saved_at" => }` -- the text is
  #   what the diff compares the original's current value to.
  #
  # Both stay valid forever (no data migration): every reader goes through
  # `Source.wrap`, so a record holding both shapes never raises.
  Source = Data.define(:digest, :text, :saved_at) do
    # nil for nothing usable stored; never raises on junk.
    def self.wrap(entry)
      case entry
      when String then entry.empty? ? nil : new(entry, nil, nil)
      when Hash
        digest = entry["digest"]
        return nil unless digest.is_a?(String) && digest.present?

        text = entry["text"]
        text = nil unless text.is_a?(String) || (text.is_a?(Array) && text.all?(String))
        new(digest, text, parse_time(entry["saved_at"]))
      end
    end

    def self.parse_time(value)
      value.is_a?(String) ? Time.iso8601(value) : nil
    rescue ArgumentError
      nil
    end

    def stored_text? = !text.nil?
  end
end
