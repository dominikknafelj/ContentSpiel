# The two names CS Studio gives a person. `PersonName.of` is the SHORT name,
# where a note, a mention or an avatar names someone: their name, and for
# someone without one the part of their email address before the at sign --
# "dana" for dana@example.com. The whole address said more than that needs to,
# to everyone who may read the record. `User#name_or_email` (and
# `Invitation#name_or_email`) is the WHOLE name, for the rest of CS Studio:
# the name, else the whole address.
#
# A value of its own because two domains that do not know each other ask it:
# notes and presence. Every place that names a person for a note (the notes
# components, a mention's text, the inbox, the toast, the mention picker, the
# mind graph's card) asks `PersonName.of`, so a name set later shows
# everywhere at once: a mention is a token with the person's id.
module PersonName
  class << self
    def of(user) = user.name.presence || user.email_address.to_s.split("@").first.presence || user.email_address

    # The letters in a person's circle: two words give the first character of
    # each of the first two ("Dana van Weiss" is "Dv"); ONE word gives its
    # first two letters, digits or emoji ("dana" is "da", "o'neil" is "on");
    # in the case they were written: the avatar's style draws them
    # upper-case (`Admin::Ui::AvatarComponent`). The only copy of the rule:
    # the scripts that draw a circle (the mind graph's card, the mention
    # picker) are handed these letters by the server and compute none.
    #
    # The odd cases, decided here: a character is a grapheme (an emoji with
    # its joiners and a letter with a combining accent stay whole); a digit
    # is as good as a letter ("7 of 9" is "7o"); a word's leading at sign or
    # other punctuation is skipped when a letter or digit follows it ("@dana"
    # is "da") and kept when nothing does ("@" is "@"); nothing at all is "".
    def initials(text)
      words = text.to_s.split
      return words.first(2).map { |word| (significant(word).first || word.grapheme_clusters.first) }.join if words.size > 1
      return "" if words.empty?

      letters = significant(words.first)
      letters.empty? ? words.first.grapheme_clusters.first : letters.first(2).join
    end

    private

    # The graphemes of a word that are a letter, a digit or an emoji.
    def significant(word)
      word.grapheme_clusters.select { |character| character.match?(/[\p{L}\p{N}\p{Emoji_Presentation}]/) }
    end
  end
end
