module Admin
  module NotesScreen
    # The passage a note quotes (decision D4; handoff "Quote block"): the
    # sunken box with the mono label "QUOTED" above the text. A copy of what
    # was selected when the note was started: nothing is highlighted in the
    # editor and it is not tracked.
    #
    # ONE drawing for the two places that show it -- above a new note's field
    # in the list and at the top of a thread -- which each wrote their own
    # and differed (one had its `figcaption` inside a `div`, where a figure's
    # caption may not stand: it is the figure's first or last child). What
    # surrounds the box is its user's: the thread pads it, the list's section
    # has a gap.
    class QuoteComponent < Admin::AdminComponent
      def initialize(quote:)
        @quote = quote.to_s
      end

      def render? = @quote.present?

      def call
        tag.figure(class: "flex flex-col gap-1 rounded-cs border border-line bg-sunken px-2.5 py-2", data: { note_quote: true }) do
          safe_join([
            tag.figcaption(t(".quoted"), class: "font-cs-mono text-label uppercase tracking-mono text-meta"),
            tag.blockquote(@quote, class: "whitespace-pre-wrap break-words text-[13px] leading-normal text-ink")
          ])
        end
      end
    end
  end
end
