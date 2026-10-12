module Publishing
  # THE ONE REFUSAL OF A PUBLISH FOR AN ADDRESS (Task 4b). Publishing never
  # leaves a live record without an address: not the record that is
  # published, and not another one. A page's new list block can take a live
  # post from the list it was in and want it at an address a subpage holds;
  # a post's newly published tags can put it under such a list itself.
  #
  # Nobody works out beforehand what a publish WOULD do to the addresses.
  # The service does it, inside its transaction, and reads what the addresses
  # answered: `PublicSite::Paths.refresh` hands back the changes that had to
  # yield (through `Publishing::Version#yields` for the copy just taken).
  # When one of them refuses, the service rolls its transaction back and
  # answers these sentences; the copy, the addresses and the audit event go
  # with it, and the version bump, the announcements and the live signals
  # were all deferred to a commit that does not come
  # (`test/integration/public_drafts_test.rb`, `assert_nothing_happened`).
  # One line stays behind: `PublicSite::Paths.yield_to_holder` has logged a
  # yield that was then taken back.
  #
  # For `Publishing::PublishChanges`, `Pages::Save` and `Posts::Save`.
  module KeepsAddresses
    private

    # One sentence per record and address among `yields` that refuses the
    # publish of `record`; empty when nothing does. Refusing are a yield of
    # `record` itself (it would be public with no address, whether or not it
    # had one) and a yield of any LIVE record that had an address until this
    # transaction and has none now. A record that was without an address
    # before is not this publish's doing and refuses nothing, or one old
    # clash would refuse every publish that looks at it.
    def lost_addresses(record, yields)
      refusing = yields.select { |change| change.record == record || (change.row_id && change.record.live?) }
      return [] if refusing.empty?

      # A page's own save refreshes before its copy is taken, so a post can
      # yield under the older picture and be given its address by the newer.
      housed = PublicPath.current.where(record_id: refusing.map { |change| change.record.id }.uniq).pluck(:record_type, :record_id, :locale).to_set
      refusing.reject { |change| housed.include?([ change.record.class.polymorphic_name, change.record.id, change.locale ]) }
        .group_by { |change| [ change.record, change.to ] }.map do |(yielder, path), changes|
          title = Locales.read(Publishing.published_all([ yielder ]).first, :title, locale: Locales.default).presence || "(untitled)"
          "The #{yielder.is_a?(Page) ? "page" : "post"} “#{title}” would get the address #{path}, which is already taken in #{changes.map { |change| change.locale.upcase }.to_sentence}"
        end
    end
  end
end
