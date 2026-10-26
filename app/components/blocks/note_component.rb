module Blocks
  # The Note block on the public site (`BlockTypes::Note`, note block spec,
  # "The public side"). Built like `Blocks::CodeComponent`: it reads the
  # block it is handed (a published view on the site, the rows in a preview)
  # and nothing else.
  #
  # Its template is promised eight names and no other (`theme_methods`):
  # `block`, `page`, `kind`, `heading`, `titled?`, `word`, `icon`, `body`.
  # `word` is promised beside `heading` because under an editor's title the
  # template still says the kind, visually hidden, before the title (spec
  # decision 6; note block plan, ruling 13). `settings` and `title` are
  # private help for those and no promise.
  #
  # AN EMPTY NOTE DRAWS NOTHING (decision 5): no text in the visitor's
  # language and none along the site's fallback, whatever its title.
  class NoteComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = !::Locales.read(block, :body).blank?

    private

    attr_reader :block, :page

    # The settings in the visitor's language, with the site's fallback for
    # the translated title (the kind is the same in every language).
    def settings = @settings ||= block.settings_object(fallback: true)

    # One of the four; a kind stored and not on the list is a Note.
    def kind = ::BlockTypes::Note.kind_of(settings&.kind)

    # The editor's title, stripped; nil for none, and for one that is only
    # the kind's word in the language shown ("Tip" on a Tip), which would
    # otherwise be heard twice after the hidden word ("Tip: Tip"; review
    # focus 6).
    def title
      text = settings&.title.to_s.strip
      text.empty? || text.casecmp?(word) ? nil : text
    end

    def titled? = !title.nil?

    # The editor's title, else the CMS's word for the kind.
    def heading = title || word

    # The kind's Lucide name: info, lightbulb, circle-alert, triangle-alert.
    def icon = ::BlockTypes::Note::ICONS.fetch(kind)

    # The text, rendered, in the visitor's language with the fallback.
    def body = rich_text(block)

    # The kind's word in the visitor's language where
    # `config/locales/public.<locale>.yml` has it, in English otherwise;
    # titled or not.
    def word
      PublicStrings.read("public.blocks.note.kinds.#{kind}")
    end
  end
end
