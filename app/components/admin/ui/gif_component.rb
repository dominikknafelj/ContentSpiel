module Admin
  module Ui
    # A GIF wherever CS Studio shows one: a note's tile
    # (`Admin::NotesScreen::FilesComponent`) and the image viewer's stage, on
    # the one script `admin--ui--gif`.
    #
    # A GIF moves. Without reduced motion it plays, like any image, and no
    # control is drawn: the stylesheet's `motion-reduce:` and `motion-safe:`
    # classes decide, not the script. WITH REDUCED MOTION the picture is in
    # the page all the same, drawn invisible (`motion-reduce:opacity-0`, so
    # it keeps its shape), and the script paints its first frame on the
    # canvas over it, under a Play button centred on the still; Play shows
    # the picture, and the button reads Pause and stands 8px in from the
    # bottom right, so it does not lie over what moves (`.admin-gif-button`).
    # No variant is made for the still: the browser has the frame already,
    # and a note's file has no variants (decision D15).
    #
    # THE HOLDER is the picture's own size, and the still lies over exactly
    # that: on a tile larger than a small GIF (the notes handoff's decision
    # 37) a canvas over the whole frame would stretch the frame.
    # - `placement: :tile` makes the holder a link to `src` in a new tab, with
    #   the caller's `link:` attributes merged in (its `title:`, its `data:`),
    #   and draws the label "GIF · name" at the frame's bottom left.
    # - `placement: :stage` makes it a bare `span` and draws no label: the
    #   viewer's head names the file, and what a click on its stage does is
    #   the viewer's. `link:` has nothing to go on there and is refused.
    #
    # `src: nil` draws an `<img>` with no address (the viewer's empty stage,
    # which its script fills): the script's `src` value is the one writer of
    # the picture's address after the first render.
    #
    # Anything else the caller hands it (`class:`, `data:`) goes on the frame:
    # a class added to its own, data merged beside the controller's.
    class GifComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "The picture keeps its file name as its alt text and the still's canvas is aria-hidden; Play and Pause are a real button named by its word, drawn only under reduced motion.",
        motion: :reduced,
        content_edges: %i[short long],
        widths: :from_container,
        interface: %i[src name placement link],
        limits: [
          "It draws no still of its own: the still is the browser's first frame of the picture, painted on a canvas, and no variant is made.",
          "What a click on the picture does is the caller's: the tile's link and its link: attributes, or nothing on the stage.",
          "Without reduced motion it draws no control: the GIF plays."
        ],
        states: %i[rest],
        script_states: { playing: [ "test/system/admin/note_files_test.rb", "a GIF plays by itself; with reduced motion it is a still with Play, which turns into Pause" ] },
        keys: %w[play pause label],
        slots: [],
        controller: "admin--ui--gif",
        keyboard: [ "test/system/admin/note_files_test.rb", "with reduced motion a GIF's Play is the Tab stop after its picture, and Enter plays and pauses it" ]
      )

      PLACEMENTS = %i[tile stage].freeze
      # The frame is the containing block of the button and the label, which
      # stand over the picture.
      FRAME_CLASS = "relative".freeze
      # The holder: the picture's own size, and the containing block of the
      # still that lies over it.
      HOLDER_CLASS = "relative block min-w-0 max-w-full".freeze
      PICTURE_CLASS = "block h-auto w-auto min-w-0 max-w-full motion-reduce:opacity-0".freeze
      # What the script says on the button, read from the frame's `data-messages`.
      MESSAGES = %w[components.ui.gif.play components.ui.gif.pause].freeze

      def initialize(src:, name:, placement: :tile, link: {}, **html)
        raise ArgumentError, "unknown GIF placement #{placement.inspect}" unless PLACEMENTS.include?(placement)
        raise ArgumentError, "a GIF on the stage is no link: link: is for a tile" if placement == :stage && link.present?

        @src = src
        @name = name
        @placement = placement
        @link = link
        @html = html
      end

      private

      attr_reader :src, :name

      def tile? = @placement == :tile

      def frame_attributes
        own = { controller: "admin--ui--gif", action: "turbo:before-cache@document->admin--ui--gif#cache",
                "admin--ui--gif-src-value": src.to_s, "admin--ui--gif-gif-value": "true", messages: messages_data(*MESSAGES) }
        # A caller's own controller or action is kept beside the frame's.
        # Its keys are Symbols first, so a String key meets the frame's own.
        data = @html.fetch(:data, {}).transform_keys(&:to_sym).merge(own) { |key, theirs, ours| %i[controller action].include?(key) ? "#{ours} #{theirs}" : ours }
        classes = [ FRAME_CLASS, @html[:class] ].compact.join(" ").split.uniq.join(" ")
        @html.merge(class: classes, data: data)
      end

      def link_attributes
        @link.merge(href: src, target: "_blank", rel: "noopener", class: "#{HOLDER_CLASS} focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-accent",
          data: @link.fetch(:data, {}).merge(turbo: false))
      end

      def picture
        image_attributes = { alt: name, class: PICTURE_CLASS, data: { "admin--ui--gif-target": "moving", action: "load->admin--ui--gif#paint" } }
        image_attributes[:loading] = "lazy" if tile?
        image_attributes[:src] = src if src.present?
        tag.img(**image_attributes)
      end
    end
  end
end
