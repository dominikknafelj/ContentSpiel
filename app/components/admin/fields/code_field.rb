module Admin
  module Fields
    # Source code (code block spec §3), for `:code` fields: a plain textarea
    # in the monospace face that neither wraps nor corrects. No code editor
    # library and no colours here; the Tab key leaves the field, as in every
    # textarea (spec decision 5, confirmed by the owner).
    #
    # ITS HEIGHT FOLLOWS THE CODE (design answer C3): six lines at least,
    # twenty-four at most, and past that the field scrolls by itself. CSS
    # alone, `field-sizing: content` between a `min-height` and a
    # `max-height` in the field's own line height (`lh`) plus its padding and
    # border, so there is nothing to measure and nothing to do again when a
    # hidden form is shown (a block in a section is drawn with the page and
    # only shown later) or when a live refresh replaces the card. A long line
    # is not wrapped (`white-space: pre`, as on the site) and scrolls inside
    # the field, whose width stays the form's. A read-only field (a form
    # someone else holds) is the same element with the same classes.
    #
    # `rows` is what a browser without `field-sizing` falls back to (a fixed
    # twelve lines between the same two bounds, with the browser's resize
    # handle); a browser that knows `field-sizing: content` ignores it.
    #
    # No `maxlength`: it would cut a paste without a word. The limit
    # (`max:`) is the server's to refuse, with the text kept in the field,
    # and from nine tenths of it a counter says how much is used.
    #
    # THE COUNTER (design answer C4) is `admin--editor--code-limit`, not the
    # plain columns' `admin--ui--char-count`: that one is always shown and is
    # a hint about a recommended length ("70 / 60 · long"); this one stays
    # out of the way until the limit is near, and the limit is real. It reads
    # "18,412 of 20,000 characters", and over the limit, in the danger ink,
    # "20,412 of 20,000 characters · 412 over". It is the field's description
    # (`aria-describedby`) only while it shows. The line beside it is a polite
    # live region the script writes at two moments only, when the counter
    # appears and when the text passes the limit: the server draws it empty,
    # because a page that arrives is read by its own means.
    class CodeField < Base
      def rows = 12

      def limit = field.options[:max]

      def counter? = limit.present?

      # Nine tenths of the limit, in whole numbers (a float's `70 * 0.9` is
      # 62.99…, one character early).
      def threshold = limit * 9 / 10

      # Characters as the server counts them (`String#length`), which is what
      # the script's `Array.from(value).length` counts too.
      def used = value.to_s.length

      def counter_shown? = used >= threshold

      def over? = used > limit

      def counter_id = "#{input_id}-count"

      def counter_text
        numbers = { used: number(used), limit: number(limit) }
        over? ? t(".over", **numbers, over: number(used - limit)) : t(".count", **numbers)
      end

      def counter_class = [ "mt-1 text-right font-cs-mono text-xs", (over? ? "text-danger-ink" : "text-meta") ]

      # 1rem + 2px: the field's own padding above and below (`py-2`) and its border.
      def input_class
        "#{setup_input_class} font-cs-mono text-sm whitespace-pre overflow-auto [tab-size:2] " \
          "[field-sizing:content] min-h-[calc(6lh+1rem+2px)] max-h-[calc(24lh+1rem+2px)]"
      end

      def described_by = (counter_id if counter? && counter_shown?)

      def wrapper_data
        return {} unless counter?

        {
          controller: "admin--editor--code-limit",
          "admin--editor--code-limit-limit-value": limit,
          "admin--editor--code-limit-from-value": threshold,
          messages: messages_data("components.fields.code_field.count", "components.fields.code_field.over")
        }
      end

      # The script only reads the field (`HeldFields::ALLOWED_ACTIONS`).
      def input_data = counter? ? { "admin--editor--code-limit-target": "input", action: "input->admin--editor--code-limit#update" } : {}

      private

      def number(value) = helpers.number_with_delimiter(value)
    end
  end
end
