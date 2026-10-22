module Admin
  module NotesScreen
    # What a thread is on, as a heading (the handoff's decision 8): the type
    # as the mono label -- "RICH TEXT", inside a section "SECTION › COLUMN 2 ·
    # RICH TEXT", the record itself "WHOLE PAGE" -- and then, for a block,
    # what tells it from the others of its type: its first words, its image's
    # file name or its place on the page, in 12px sans, dim, on the same line
    # and cut with an ellipsis. The heading of a group in the list and of
    # row 2 in the thread view; `level` is the heading's tag in each.
    #
    # `name` is a `Notes::Heading::Name` (`Notes::Listing#heading_of`), nil for
    # the record itself; `type` is the kind of record ("page", "post",
    # "media"). Nothing here queries.
    class SubjectComponent < Admin::AdminComponent
      def initialize(name:, type:, level: :h4, **html)
        @name = name
        @type = type
        @level = level
        @html = html
      end

      def call
        content_tag(@level, **@html, class: [ "flex min-w-0 items-baseline gap-2", @html[:class] ]) do
          safe_join([
            tag.span(helpers.note_subject_label(@name, @type), class: "shrink-0 font-cs-mono text-label uppercase tracking-mono text-meta", data: { note_subject_type: true }),
            (tag.span(detail, class: "min-w-0 truncate text-xs text-dim", data: { note_subject_words: true }) if detail)
          ].compact)
        end
      end

      private

      def detail = @detail ||= helpers.note_subject_detail(@name)
    end
  end
end
