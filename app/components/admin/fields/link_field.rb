module Admin
  module Fields
    # A `:link` field: a typed address, or a page or a post chosen by its title
    # (the issue of 2026-11-01). A text input for the address, not `type="url"`: a site-relative
    # address ("/about") is a link and no browser URL; `inputmode="url"` keeps
    # the URL keyboard. `ContentModel::FieldTypes` is the real check, on the
    # server.
    #
    # THE FIELD'S VALUE IS THE ONE NAMED INPUT, whichever of the two it holds:
    # choosing writes the reference into it and fires `change`, so autosave,
    # the stale check, a held form's rewrite and live refresh treat it as any
    # other text input. While it holds a reference the input is `hidden` (it is
    # still submitted) and the chosen target's title stands in its place. The
    # search box beside it has no name and so is never sent, and its events
    # stop at this field's root: a half-typed title in the named input would be
    # autosaved and refused, which is why this is not one box.
    #
    # WHAT IS SHOWN of a reference is the target's title, only when the viewer
    # may read it (`LinkTargets.readable`), and the same neutral words for what
    # they can't and what is gone, so the field tells nobody what exists. The
    # reference itself is a form value and no text anywhere, and carries an id
    # and no title.
    #
    # A HELD OR VIEW-ONLY FORM needs nothing of its own: `HeldFields` turns both
    # inputs read-only, disables the button and strips the actions, and the
    # stylesheet's `read-only:hidden`, `disabled:hidden` and `peer-read-only:hidden`
    # take the search away, in a form frozen by the browser too (`freeze.js`).
    class LinkField < Base
      UNAVAILABLE_KEY = "admin.components.fields.link_field.unavailable".freeze

      # A reference reads as its target's title in the default language, or as
      # the neutral words; an address as itself.
      def self.display(_field, value)
        reference = ContentModel::LinkReference.parse(value)
        return value.to_s unless reference

        target = LinkTargets.readable(reference)
        target ? title_of(target, ::Locales.default) : I18n.t(UNAVAILABLE_KEY)
      end

      def self.title_of(record, locale)
        record.title(locale: locale).presence || I18n.t("admin.components.fields.link_field.untitled")
      end

      private

      def reference = @reference ||= ContentModel::LinkReference.parse(value)

      def target = defined?(@target) ? @target : (@target = reference && LinkTargets.readable(reference))

      def editing_locale = locale || ::Locales.default

      def chosen_title
        return unless reference

        target ? self.class.title_of(target, editing_locale) : t(".unavailable")
      end

      # Whether to say a chosen target has no public address now. Only of a
      # target this person may read: of any other, it would say something.
      def not_public?
        return false unless target

        !PublicSite::Resolver.visible?(target) || PublicSite::Urls.new.path_for(target, editing_locale).nil?
      end

      def search_url = helpers.admin_link_targets_path

      def group_id = "#{input_id}-group"
    end
  end
end
