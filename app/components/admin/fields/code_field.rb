module Admin
  module Fields
    # Source code (code block spec §3), for `:code` fields: a plain textarea
    # in the monospace face that neither wraps nor corrects. No code editor
    # library and no colours here; the Tab key leaves the field, as in every
    # textarea (spec decision 5, confirmed by the owner).
    #
    # No `maxlength`: it would cut a paste without a word. The limit
    # (`max:`) is the server's to refuse, with the text kept in the field,
    # and from nine tenths of it a counter says how much is used.
    #
    # The counter is `admin--editor--code-limit`, not the plain columns'
    # `admin--ui--char-count`: that one is always shown and is a hint about a
    # recommended length ("70 / 60 · long"); this one stays out of the way
    # until the limit is near, and the limit is real.
    class CodeField < Base
      COUNTER_FROM = 0.9

      def rows = 12

      def limit = field.options[:max]

      def counter? = limit.present?

      def threshold = (limit * COUNTER_FROM).floor

      # Characters as the server counts them (`String#length`), which is what
      # the script's `Array.from(value).length` counts too.
      def used = value.to_s.length

      def counter_shown? = used >= threshold

      def over? = used > limit

      def counter_id = "#{input_id}-count"

      def counter_text = t(".count", used: helpers.number_with_delimiter(used), limit: helpers.number_with_delimiter(limit))

      def counter_class = [ "mt-1 text-right font-cs-mono text-xs", (over? ? "text-warn-ink" : "text-meta") ]

      def input_class = "#{setup_input_class} font-cs-mono text-sm whitespace-pre overflow-auto [tab-size:2]"

      def wrapper_data
        return {} unless counter?

        {
          controller: "admin--editor--code-limit",
          "admin--editor--code-limit-limit-value": limit,
          "admin--editor--code-limit-from-value": threshold,
          messages: messages_data("components.fields.code_field.count")
        }
      end

      # The script only reads the field (`HeldFields::ALLOWED_ACTIONS`).
      def input_data = counter? ? { "admin--editor--code-limit-target": "input", action: "input->admin--editor--code-limit#update" } : {}
    end
  end
end
