module Notes
  # A mention in a stored body is the token `@[<user id>]` (notes spec §3.2):
  # an id, so renaming a user changes how old mentions read and a deleted one
  # reads "a deleted user".
  #
  # A textarea can't show a name for a token, so the composer shows
  # "@Dana Smith" and sends, beside the text, the names its picker inserted
  # and their ids; `tokenize` puts the tokens in before the service sees the
  # body, and `display` is the way back for the edit form. The map comes from
  # the browser and is not trusted for anything but this substitution: who
  # may be mentioned is checked by the service on the ids that result.
  module Mentions
    # At most 18 digits: every such number fits a bigint (19 digits at most).
    # A longer one, typed by hand, is nobody's id; unbounded, it would pass
    # validation and raise a RangeError when `mentioned_user_ids` is saved.
    # It stays text.
    TOKEN = /@\[(\d{1,18})\]/

    # How many different people one message may mention. A picker never gets
    # near it; a forged body listing ids would otherwise make the service
    # look every one of them up and judge each one's access. The services
    # refuse a longer list before any of that (`Authorization#body_errors`).
    MAX = 20

    def self.ids(body) = body.to_s.scan(TOKEN).flatten.map(&:to_i).uniq

    # The longest name first: "@Dana Smith" must not be read as "@Dana"
    # followed by " Smith". A block as the replacement, so a `\1` in a name is
    # text.
    def self.tokenize(text, names)
      names.to_h.sort_by { |name, _id| -name.to_s.length }.reduce(text.to_s) do |body, (name, id)|
        next body unless name.to_s.present? && id.to_s.match?(/\A\d+\z/)

        body.gsub("@#{name}") { "@[#{id}]" }
      end
    end

    # `[text, { name => id }]`, the name as a note says it (`Notes.name_of`:
    # the same one the picker inserts). A token whose user is not in
    # `users_by_id` (deleted since) is left as it is, so saving the edit
    # doesn't turn it into loose text.
    def self.display(body, users_by_id)
      names = {}
      text = body.to_s.gsub(TOKEN) do |token|
        user = users_by_id[Regexp.last_match(1).to_i]
        next token unless user

        name = Notes.name_of(user)
        names[name] = user.id
        "@#{name}"
      end
      [ text, names ]
    end
  end
end
