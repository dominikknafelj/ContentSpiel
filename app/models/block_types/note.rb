module BlockTypes
  # A highlighted note in the flow of a page (note block spec): a kind, an
  # optional title of the editor's own and a short text. The design is
  # Claude Design's (B1 to B3, 2026-10-13).
  #
  # WHERE EACH VALUE LIVES. The kind is the same in every language and is a
  # setting; the title is translated, the first translated schema field of a
  # built-in type (`translated_settings`); the text is the block's ordinary
  # rich-text `body`. So no column, no migration and no service, as for the
  # Code block. Nothing is required: the picker makes an empty Note first,
  # and the public component draws nothing until there is text.
  #
  # THE KINDS are four and closed. `KINDS` is what CS Studio's segmented
  # control says (a literal, as a select's choices are); the visitor's word
  # is the public site's key `public.blocks.note.kinds.<kind>`; `ICONS` are
  # the Lucide names the default template draws, which CS Studio draws on a
  # note's card and tile in its icon partial's spelling (`studio_icon`,
  # `t.icon … for_block:`; note block plan, rulings 11 and 12). They live
  # here, not on the component, because the tile's line (`summary`) and the
  # icon need them and a model names a component only to register it (note
  # block plan, ruling 1). A kind that is stored and not on the list reads as
  # a Note (`kind_of`), everywhere.
  module Note
    KINDS = { "note" => "Note", "tip" => "Tip", "important" => "Important", "warning" => "Warning" }.freeze
    ICONS = { "note" => "info", "tip" => "lightbulb", "important" => "circle-alert", "warning" => "triangle-alert" }.freeze
    DEFAULT = "note"
    # A title is a heading of one line.
    TITLE_LENGTH = 80
    # The text on the tile is cut at the length the tile cuts every line at.
    SUMMARY_LENGTH = ContentModel::BlockTypeDefinition::SUMMARY_LENGTH

    def self.kind_of(value) = KINDS.key?(value.to_s) ? value.to_s : DEFAULT

    # CS Studio's icon of one note, on its card's head and its tile: its
    # kind's, spelt as `BlockTypeDefinition::ICONS` and the icon partial
    # spell it (`circle_alert` for Lucide's `circle-alert`). Read from the
    # rows' settings: CS Studio draws the rows, never a published copy.
    def self.studio_icon(block) = ICONS.fetch(kind_of(block.settings.to_h["kind"])).tr("-", "_")

    def self.register
      BlockTypes.register :note do |t|
        t.label "Note"
        # The picker's icon is the Note's own, the kind a new block starts
        # with; a block's card and tile show its kind's (plan ruling 12).
        t.icon "info", for_block: ->(block) { Note.studio_icon(block) }
        t.field :kind, :select, options: KINDS, default: DEFAULT, control: :segmented
        t.field :title, :string, translated: true, max: TITLE_LENGTH, placeholder_from: :kind,
                help: "Leave it empty to head the note with its kind."
        t.uses :body
        t.component Blocks::NoteComponent
        # `kind` is one of the four (an unknown stored kind is "note");
        # `heading` the editor's title in the language shown, else the
        # CMS's word for the kind in it; `titled?` whether the heading is the
        # editor's; `word` the CMS's word for the kind, titled or not (the
        # hidden word before a title, spec decision 6; plan ruling 13);
        # `icon` the kind's Lucide name; `body` the text, rendered.
        t.theme_methods :block, :page, :kind, :heading, :titled?, :word, :icon, :body
        # Four per kind, in the order of `KINDS`; their values are the default
        # theme's (`tokens.css`, defined from the base tokens), and a strong
        # band re-values them (`sections.css`).
        t.tokens themed: KINDS.keys.flat_map { |kind| %W[note-#{kind}-ground note-#{kind}-line note-#{kind}-ink note-#{kind}-border] }
        t.stylesheet "note.css"
        t.summary ->(block, locale:) { Note.summary(block, locale: locale) }
        # The guide's own example (a Tip with a title of its own), with the
        # title in the canary's three languages and a text the canary reads.
        t.sample settings: { "kind" => "tip" },
                 translations: { "en" => { title: "Before you publish" }, "de" => { title: "Note title de" }, "es" => { title: "Note title es" } },
                 body: "Check the **address** of the page first.",
                 shows: [ "Before you publish", "Check the", "content-block--note-tip" ]
      end
    end

    # The tile's line of a closed Note, as parts (note block spec, "CS
    # Studio"): the editor's title or the kind's label as CS Studio says it,
    # " · ", and the start of the text, or "Empty" in the meta colour for a
    # note with no text in this language. The kind's icon is not a part: the
    # tile draws it before the line, in place of the type's (`t.icon …
    # for_block:`; plan ruling 12).
    def self.summary(block, locale:)
      settings = block.settings_object(locale: locale)
      kind = kind_of(settings&.kind)
      word = settings&.title.presence || KINDS.fetch(kind)
      first = block.body_document(locale: locale).plain_paragraphs.first.to_s.truncate(SUMMARY_LENGTH).presence

      [ [ :text, "#{word} · " ], (first ? [ :text, first ] : [ :hint, :empty ]) ]
    end
  end
end
