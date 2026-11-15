module Admin
  module Ui
    # The image viewer: a picture opened over CS Studio, fitted to the
    # window, with its name and facts in the head, the arrows to step through
    # its siblings, the position, Open original and Download. Its first
    # caller is a note's pictures (`Admin::NotesScreen::FilesComponent`).
    #
    # Drawn once per CS Studio page, by the admin layout, outside `#content`
    # and every form, like the media picker: one dialog (one set of ids)
    # however many threads a page shows, the rail's, the slide-over's, the
    # sheet's and the Notes screen's all reaching it. It is drawn EMPTY: no
    # name, no facts and a picture with no address, so the layout holds
    # nothing of anyone's notes. `admin--ui--image-viewer`, on the dialog,
    # fills it from the pressed thumbnail (a plain click on a
    # `[data-image-viewer-item]` link, its group read once from the link's
    # `[data-image-viewer-group]`) and takes it all back at
    # `turbo:before-cache` and `disconnect`.
    #
    # THE FRAME is `DialogComponent` at the `viewer` step: the title is the
    # file name (truncated on one line, and whole as the dialog's accessible
    # name), the facts its title aside, Close the dialog's own. Its body is
    # a padding-less flex column the stage fills.
    #
    # THE STAGE is `cs-sunken`, the picture centred on it at its own size and
    # never enlarged. The picture is `Admin::Ui::GifComponent` on the stage
    # placement, with `gif: false` until the script says the picture is a
    # GIF, so a GIF's still and Play are the thread's own part. Its `<img>`
    # is also the viewer's `picture` target, whose `load` and `error` the
    # viewer hears. The stage is a size container
    # (`.admin-image-viewer__stage`) and the picture's height is capped at
    # `100cqh`: a percentage would resolve against the GIF's holder, whose
    # height is the picture's own, and cap nothing; the container unit is a
    # length, so the picture's width follows it and the holder (and a
    # GIF's still over it) stays the picture's own size. The notice and the
    # loading line stand in the same grid cell as the picture.
    #
    # The round arrows stand over the stage's edges and come after the
    # picture in the markup, so they need no layer; off a phone only (the
    # phone's are the foot's small secondaries, so one pair is drawn at a
    # width), and `hidden` until a group has more than one picture. At the
    # ends the script disables one (the real `disabled`, out of the Tab
    # order) and it keeps its circle and its place on the sunken ground.
    #
    # There is no primary: nothing here is the area's one action. Download
    # is secondary and Open original tertiary.
    class ImageViewerComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A native modal dialog named by the file name, with Close, Previous image and Next image as buttons, Open original and Download as links, and a polite announcement of the name and position at each step; Escape, Close and the backdrop close it and the focus goes back to the picture that opened it.",
        motion: :reduced,
        content_edges: %i[long many missing],
        widths: :fixed_width,
        interface: %i[],
        limits: [
          "It is drawn once, by the admin layout, and opened only by a plain click on a [data-image-viewer-item] link.",
          "The picture is fitted: no zoom, pan or swipe; Open original shows it at its own size in a tab.",
          "It steps within the opener's [data-image-viewer-group] only, read once at opening."
        ],
        states: %i[rest],
        script_states: {},
        keys: %w[previous next position open_original download failed loading stepped],
        slots: [],
        controller: "admin--ui--image-viewer",
        keyboard: nil
      )

      DIALOG_ID = "image-viewer".freeze

      # What the script writes: the foot's position and the announcement at a
      # step, read from the dialog's `data-messages`.
      MESSAGES = %w[components.ui.image_viewer.position components.ui.image_viewer.stepped].freeze

      TARGET = "admin--ui--image-viewer-target".freeze

      # A stage arrow: 40px on the popover with a 1px edge and shadow 2;
      # disabled, the sunken ground, the arrow in meta and no shadow, in the
      # same circle and place.
      ARROW_CLASS = "absolute top-1/2 -translate-y-1/2 grid size-10 cursor-pointer place-items-center rounded-full border border-line bg-popover text-ink shadow-2 " \
                    "disabled:cursor-not-allowed disabled:bg-sunken disabled:text-meta disabled:shadow-none " \
                    "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent max-sm:hidden".freeze

      private

      def target(name) = { TARGET => name }

      # The `<img>` of the GIF part, which is also the viewer's picture:
      # fitted to the stage and never enlarged (`w-auto h-auto` and the
      # caps), the checkerboard behind its own box from the stage's rule.
      def picture_html
        { class: "max-h-[100cqh] object-contain",
          data: { TARGET => "picture", action: "error->admin--ui--image-viewer#failed load->admin--ui--image-viewer#loaded" } }
      end

      def stage_arrow(name, side:, icon:)
        tag.button(type: "button", hidden: true, "aria-label": t(".#{name}"), class: "#{ARROW_CLASS} #{side}",
          data: { TARGET => name, action: "admin--ui--image-viewer##{name}" }) do
          helpers.render "admin/shared/icon", name: icon, size: "size-[18px]"
        end
      end

      def phone_arrow(name, target_name:, icon:)
        tag.button(type: "button", hidden: true, "aria-label": t(".#{name}"), class: "#{Admin::Ui::ButtonComponent.classes(:secondary, size: :small)} sm:hidden",
          data: { TARGET => target_name, action: "admin--ui--image-viewer##{name}" }) do
          helpers.render "admin/shared/icon", name: icon, size: "size-4"
        end
      end
    end
  end
end
