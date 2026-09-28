class Avo::Resources::ContentBlock < Avo::BaseResource
  self.icon = "tabler/outline/stack-2"

  # ContentBlock has no name of its own, and Avo's fallback title would be the
  # bare id -- which tells an editor nothing in a list of blocks. The type is
  # what distinguishes one row from the next.
  self.title = :block_type

  # `settings` no longer has a field of its own (the typed-fields tool below
  # writes it instead), so nothing else would tell Avo to let this key
  # through `permitted_params` -- same reason `Avo::Resources::Page` permits
  # `content_blocks_attributes` for its own resource tool.
  self.extra_params = [ { settings: {} } ]

  def fields
    field :id, as: :id
    field :owner, as: :belongs_to, polymorphic_as: :owner, types: [ ::Page ]
    field :position, as: :number
    # {label => value} -- see the comment on Avo::Resources::Post's own
    # `content_type` field for why this direction (not the content-type
    # filter's).
    field :block_type, as: :select, options: ::BlockTypes.all.to_h { |definition| [ definition.label, definition.name ] }

    # `image`/`caption` are existing columns every block type either
    # `uses` or doesn't -- shown unconditionally rather than gated on the
    # type, same as the page form's inline row (a block's type is routinely
    # changed while drafting). `settings`, by contrast, *is* type-specific
    # (open-types spec §6): the typed-fields tool below renders one input per
    # field the record's own `block_type` actually declares, replacing the
    # raw `key_value` editor this used to be.
    field :image, as: :file

    # Same tabs-plus-locale-accessors arrangement as Avo::Resources::Post and
    # Avo::Resources::Page -- see the note in the Post resource. A rich-text
    # block's `body` isn't editable here: it's a per-locale JSON document
    # (tiptap spec §3.1) that CS Studio edits; Avo goes in tiptap Task 10.
    tabs do
      ::Locales.enabled.each do |locale|
        tab title: locale.to_s.upcase do
          field ::Mobility.normalize_locale_accessor(:caption, locale).to_sym,
            as: :text, name: "Caption"
        end
      end
    end

    tool Avo::ResourceTools::TypedFields, show_on: :forms
  end
end
