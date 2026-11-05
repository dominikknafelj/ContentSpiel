module Forms
  # The submissions list's one line about a submission. COMPUTED, NEVER STORED: an unencrypted copy of answers would be the
  # very thing encryption keeps out of the table, so the list decrypts the
  # rows of the page it shows (50 at most) and asks this for each.
  #
  # The first two answers, in the form's order as it was at the send, whose
  # type says `summary` (`Forms::FieldType#summary`: short text and email
  # among the built-ins, a gem's type by its own say), each as it reads
  # (`display`), left out when empty, joined with " · " and cut at `LIMIT`
  # characters. A long text, a choice and a checkbox are not in it: a
  # message is too long for a line and a choice says nothing of who sent
  # it. A type no longer registered is left out too.
  #
  # nil when no answer qualifies (the list draws "—") and for a submission
  # the site's keys can no longer read (`Submission#readable?`; the list
  # words that "Can't be read").
  module Summary
    TAKEN = 2
    LIMIT = 80
    SEPARATOR = " · ".freeze

    module_function

    def of(submission)
      return nil unless submission.readable?

      texts = Array(submission.answers).lazy.filter_map do |row|
        next unless row.is_a?(Hash) && FieldTypes.find(row["type"])&.summary

        row["display"].to_s.squish.presence
      end.first(TAKEN)
      return nil if texts.empty?

      texts.join(SEPARATOR).truncate(LIMIT, omission: "…")
    end
  end
end
