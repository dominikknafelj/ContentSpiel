# What a person is called where a short name is wanted (the notes handoff's
# decision 36, the presence handoff's item 7): their name, and for someone
# without one the part of their email address before the at sign -- "dana"
# for dana@example.com. The whole address said more than a note or an avatar
# needs to, to everyone who may read the record.
#
# A value of its own because two domains that do not know each other ask it:
# notes (`Notes.name_of`, which answers this) and presence. `User#display_name`,
# which the rest of CS Studio uses and which answers the whole address, is
# not changed.
module PersonName
  class << self
    def of(user) = user.name.presence || user.email_address.to_s.split("@").first.presence || user.email_address

    # The letters in a person's circle: the first character of each of the
    # first two words of what they are called -- "Dana van Weiss" is "Dv",
    # "dana" is "d" -- in the case they were written: the avatar's style
    # draws them upper-case (`Admin::Ui::AvatarComponent`). It is the rule
    # notes' avatar always had, taken as it was: ONE word gives ONE letter.
    # Asked with the text and not the user, because notes also draws a circle
    # for "a deleted user".
    #
    # The odd cases, decided here: a character is a grapheme (an emoji with
    # its joiners and a letter with a combining accent stay whole); a digit
    # is as good as a letter ("7 of 9" is "7o"); a word's leading at sign or
    # other punctuation is skipped when a letter or digit follows it ("@dana"
    # is "d") and kept when nothing does ("@" is "@"); nothing at all is "".
    def initials(text)
      text.to_s.split.first(2).map { |word| first_character(word) }.join
    end

    private

    def first_character(word)
      characters = word.grapheme_clusters
      characters.find { |character| character.match?(/[\p{L}\p{N}\p{Emoji_Presentation}]/) } || characters.first
    end
  end
end
