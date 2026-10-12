module Publishing
  # How a service answers `Publishing::AddressTaken`. The refusal itself is
  # in one place, `take!` of `Publishing::Version`; a service that takes a copy
  # rescues the error outside its transaction (which the error has rolled
  # back: the copy, the addresses, the record's own row and the audit event,
  # with the version bump, the announcements and the live signals that were
  # deferred to a commit that does not come) and answers this.
  #
  # For `Publishing::PublishChanges`, `Pages::Save` and `Posts::Save`.
  module KeepsAddresses
    private

    # A failure with one sentence per record and address that would be lost.
    def address_taken(record, error)
      failure(record, error.lost.group_by { |change| [ change.record, change.to ] }.map do |(yielder, path), changes|
        title = Locales.read(Publishing.published_all([ yielder ]).first, :title, locale: Locales.default).presence || "(untitled)"
        "The #{yielder.is_a?(Page) ? "page" : "post"} “#{title}” would get the address #{path}, which is already taken in #{changes.map { |change| change.locale.upcase }.to_sentence}"
      end)
    end
  end
end
