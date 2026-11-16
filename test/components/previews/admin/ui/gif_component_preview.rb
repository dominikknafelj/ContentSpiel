module Admin
  module Ui
    # `Admin::Ui::GifComponent` at rest: a GIF's tile, which plays, or under
    # reduced motion is its still with Play. The picture is the suite's small
    # fixture GIF, inline, since a preview has no note to serve it from.
    class GifComponentPreview < ViewComponent::Preview
      def rest
        src = "data:image/gif;base64,#{Base64.strict_encode64(Rails.root.join('test/fixtures/files/small.gif').binread)}"
        render Admin::Ui::GifComponent.new(src: src, name: "loop.gif", link: { title: "Open loop.gif in a new tab" },
          class: Admin::NotesScreen::FilesComponent::PICTURE_BOX_CLASS)
      end
    end
  end
end
