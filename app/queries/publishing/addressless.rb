module Publishing
  # Whether a LIVE page or post is left without an address (drafts plan, task
  # 6, addition 3): it yielded its address to another record (a page
  # published onto it, a list block published away, a tag), and a visitor who
  # follows a link to it is told "not found". Nobody is refused for it
  # (`Publishing.keep_address!` refuses only a record's OWN address), so this
  # is how a person finds out.
  #
  # Cheap in the common case: one statement says the record has a current
  # address. Only a live, kept record without one pays for more, because
  # "has no address" alone is also what a post that nothing lists looks like
  # (the editor says "Not listed on any page yet" for that, and it is no
  # fault):
  #
  # - a page: it has a slug in the default language and still no address (a
  #   page under one without an address has none either; the parent is
  #   marked too);
  # - a post: some list block, AS PUBLISHED, lists it (`Publishing::Listing`),
  #   so a page it belongs on exists and the post still has no address.
  class Addressless
    class << self
      def record?(record, now: Time.current)
        return false if record.published_at.nil? || record.published_at > now || record.trashed?
        return false if PublicPath.current.exists?(record_type: record.class.polymorphic_name, record_id: record.id)

        case record
        when Page then ::Locales.read(record, :slug, locale: ::Locales.default).present? && !record.root?
        when Post then listed?(::Publishing.published(record, now: now), now)
        else false
        end
      end

      private

      def listed?(post, now)
        blocks = Listing.blocks(now: now)
        tags = Listing.filter_tags(blocks)
        blocks.any? { |block| Listing.lists?(block, post, tags: tags) }
      end
    end
  end
end
