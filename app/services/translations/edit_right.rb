module Translations
  # The "edit right" of a translatable record (translation helpers spec
  # §3.4/§6.3): exactly the right an ordinary edit of that record, in its
  # current state, would need -- so "Still correct — mark up to date" (`Translations::
  # Confirm`) and, later, requesting an AI suggestion (`AI::Translate`) can
  # never do more than typing into the editor could:
  #
  # * a page or post: `<prefix>.edit`, plus `<prefix>.publish` once it's
  #   published (live or scheduled) -- the rule
  #   `Pages::Save`/`Posts::Save` enforce: whoever may change a published
  #   record may publish it (drafts spec D5);
  # * a block: its owner's, the same rule (`ContentBlocks::OwnerPermissions`);
  # * an image: `media.manage`, or being its uploader with `media.upload`
  #   (`Media::Ownership`, what `Media::Save` asks);
  # * the site settings: `settings.manage`, what `Settings::Save` asks.
  #
  # Like `OwnerPermissions`, it yields each key to the including service,
  # which answers with its own `authorize!(key, record)` -- so `authorize!(`
  # stays written in that service's `#call`, where the service contract test
  # (test/services/service_contract_test.rb) looks for it. Returns the
  # refused key (what the service hands `denied`), or nil.
  module EditRight
    include ContentBlocks::OwnerPermissions
    include Media::Ownership

    private

    def edit_refusal(record, &allowed)
      case record
      when Page, Post
        prefix = record.is_a?(Page) ? "pages" : "posts"
        keys = [ "#{prefix}.edit" ]
        keys << "#{prefix}.publish" if record.published_at.present?
        keys.find { |key| !allowed.call(key) }
      when ContentBlock then owner_refusal(record.owner, &allowed)
      when Media::Asset then "media.manage" unless allowed.call("media.manage") || uploader_may_manage?(record)
      when SiteSetting then "settings.manage" unless allowed.call("settings.manage")
      else raise ArgumentError, "no edit right defined for #{record.class.name}"
      end
    end
  end
end
