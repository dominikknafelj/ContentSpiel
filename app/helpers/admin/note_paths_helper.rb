module Admin
  # The two leading arguments of every `admin_record_note*_path`: which kind
  # of record, and which one. Route segments are a controller's and a
  # component's business, so this lives here and not on `Notes`.
  module NotePathsHelper
    TYPES = { "Page" => "page", "Post" => "post", "Media::Asset" => "media" }.freeze # i18n-ok: class names keyed to route segments, not copy

    def note_args(container) = [ TYPES.fetch(container.class.polymorphic_name), container.id ]

    # What a thread is on, as the mono label of its group's heading says it
    # (the handoff's decision 8): the record itself ("Whole page"), or the
    # block's type -- "Rich text", and inside a section "Section › Column 2 ·
    # Rich text". `name` is a `Notes::Heading::Name`, or nil for the record
    # itself. A block has no name of its own in this CMS, so its type is its
    # label and `note_subject_detail` is what tells two of a type apart.
    def note_subject_label(name, type)
      return t("admin.notes.subject.#{type}") if name.nil?

      name.section ? t("admin.notes.subject.in_section", section: name.section, column: name.column, type: name.type) : name.type
    end

    # The block's first words, its image's file name, or its place on the
    # page for a block with neither ("Block 3"). Nil for the record itself.
    def note_subject_detail(name)
      return if name.nil?

      name.words.presence || name.file_name.presence || t("admin.notes.subject.block", position: name.position)
    end
  end
end
