module Admin
  # The box at the top of an explicit-save form after a 422 (design pass spec
  # §4): "N things need fixing" and one line per message, each linking to the
  # field it is about. `role="alert"` + `tabindex="-1"` + `autofocus` so a
  # screen reader announces it and keyboard focus lands on it when Turbo
  # renders the 422.
  #
  # `errors` is `{ "field" => [ "message", ... ] }`, an `ActiveModel::Errors`,
  # or a plain array of strings (the service layer's `result.errors`, which
  # are already full sentences with no field to link to). `field_ids` maps a
  # field to the DOM id its link jumps to; a field without one prints its
  # message as plain text.
  #
  # When does a message get its field name in front? Rails messages are
  # fragments ("has already been taken") and need "Email address" before them;
  # but some are already whole sentences and must print as they are -- the
  # password rule "Use at least 12 characters." (`User`, ends with a full
  # stop) and the password blank/too-long messages, which carry their own
  # "Password " prefix (config/locales/en.yml). So: as is when the message
  # ends with a full stop, or already starts with the humanized field name, or
  # belongs to `base`; otherwise prefixed.
  class ErrorSummaryComponent < AdminComponent
    def initialize(errors:, field_ids: {})
      @pairs = normalize(errors)
      @field_ids = field_ids.transform_keys(&:to_s)
    end

    def render? = @pairs.any?

    private

    attr_reader :field_ids

    # [field, sentence] per error. Built at render time, not in `initialize`:
    # a sentence may ask `t`, which nothing can before the component renders.
    def entries = @entries ||= @pairs.map { |field, message| [ field, sentence_for(field, message) ] }

    def heading
      t(".heading", count: entries.size)
    end

    def normalize(errors)
      pairs =
        case errors
        when ActiveModel::Errors then errors.messages.flat_map { |field, messages| messages.map { |message| [ field.to_s, message ] } }
        when Hash then errors.flat_map { |field, messages| Array(messages).map { |message| [ field.to_s, message ] } }
        else Array(errors).map { |message| [ "base", message ] }
        end
      pairs.map { |field, message| [ field, message.to_s ] }
    end

    def sentence_for(field, message)
      return message if field == "base" || message.end_with?(".")

      name = field.humanize # i18n-ok: the field's English name is out of scope until attribute names are translated (docs/reference/i18n.md)
      message.downcase.start_with?(name.downcase) ? message : t(".sentence", field: name, message: message)
    end
  end
end
