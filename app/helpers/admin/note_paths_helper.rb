module Admin
  # The two leading arguments of every `admin_record_note*_path`: which kind
  # of record, and which one. Route segments are a controller's and a
  # component's business, so this lives here and not on `Notes`.
  module NotePathsHelper
    TYPES = { "Page" => "page", "Post" => "post", "Media::Asset" => "media" }.freeze # i18n-ok: class names keyed to route segments, not copy

    def note_args(container) = [ TYPES.fetch(container.class.polymorphic_name), container.id ]

    # What a thread is on, as its group's heading says it: the record itself
    # ("This page"), or the block the way its card names it -- with its column
    # inside a section (`Admin::EditorScreen::PanelTitleComponent`'s own key).
    # A block has no name of its own in this CMS, so its type is its name.
    def note_subject_name(record, container, type)
      return t("admin.notes.subject.#{type}") if record.nil? || record == container

      label = record.definition&.label || record.block_type
      record.section_id ? t("admin.components.editor_screen.panel_title.title", type: label, column: record.section_column) : label
    end
  end
end
