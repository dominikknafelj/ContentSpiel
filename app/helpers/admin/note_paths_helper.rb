module Admin
  # The two leading arguments of every `admin_record_note*_path`: which kind
  # of record, and which one. Route segments are a controller's and a
  # component's business, so this lives here and not on `Notes`.
  module NotePathsHelper
    TYPES = { "Page" => "page", "Post" => "post", "Media::Asset" => "media" }.freeze # i18n-ok: class names keyed to route segments, not copy

    # Every route a notes row may name: the three records a note's container
    # can be (`Dashboard::NotesForYou#route`, `Dashboard::OpenThreads`, both
    # through `Audit::Sentence.route_for`). A route name handed up from a
    # query is DATA from below, and `public_send` on unchecked data is a
    # method call chosen by data; so the name is checked against this list
    # before it is called, however trustworthy its source looks today, as
    # `Admin::AuditScreen::SentenceComponent::ROUTES` and
    # `Admin::JumpHelper::JUMP_ROUTES` do for theirs. Symbols only:
    # `"admin_page_path"` is not on the list.
    NOTE_ROUTES = %i[admin_page_path admin_post_path admin_media_path].freeze

    def note_args(container) = [ TYPES.fetch(container.class.polymorphic_name), container.id ]

    # Where a row of the inbox or of "Open threads" leads: its route (a name,
    # arguments and params: `Audit::Sentence::Route`) resolved with `options`,
    # the request's URL options. The ONE place a notes screen turns a route
    # name into a path (the two row components and the delivery the toast
    # asks for). A name that is not on the list raises and calls nothing: a
    # new kind of record a note can be on must be added here on purpose.
    def note_route_path(route, **options)
      raise ArgumentError, "#{route.name.inspect} is not a route a note may link to (Admin::NotePathsHelper::NOTE_ROUTES)" unless NOTE_ROUTES.include?(route.name)

      public_send(route.name, *route.args, **route.params, **options)
    end

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
