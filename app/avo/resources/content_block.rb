class Avo::Resources::ContentBlock < Avo::BaseResource
  self.icon = "tabler/outline/stack-2"

  # ContentBlock has no name of its own, and Avo's fallback title would be the
  # bare id -- which tells an editor nothing in a list of blocks. The type is
  # what distinguishes one row from the next.
  self.title = :block_type

  def fields
    field :id, as: :id
    field :page, as: :belongs_to
    field :position, as: :number
    field :block_type, as: :select, enum: ::ContentBlock.block_types

    # Which of these matters depends on `block_type` (rich_text -> body,
    # image -> image + caption, post_list -> settings). They are all shown
    # rather than gated on the type: a block's type is routinely changed while
    # drafting, and the page form's inline editor is the same way.
    field :image, as: :file
    field :settings, as: :key_value,
      key_label: "Setting", value_label: "Value",
      help: "A post_list block's query criteria: content_type, tag, limit."

    # Same tabs-plus-locale-accessors arrangement as Avo::Resources::Post and
    # Avo::Resources::Page -- see the note in the Post resource. This is where
    # a block's rich text gets the full editor; the page form's inline rows
    # deliberately keep it to a plain HTML textarea (see the resource tool).
    tabs do
      ::Mobility.available_locales.each do |locale|
        tab title: locale.to_s.upcase do
          field ::Mobility.normalize_locale_accessor(:caption, locale).to_sym,
            as: :text, name: "Caption"
          field ::Mobility.normalize_locale_accessor(:body, locale).to_sym,
            as: :trix, name: "Body"
        end
      end
    end
  end
end
