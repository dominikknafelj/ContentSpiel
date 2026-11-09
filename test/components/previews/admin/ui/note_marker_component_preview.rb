module Admin
  module Ui
    # `Admin::Ui::NoteMarkerComponent`: the read bubble on a row, the unread
    # one (accent, "3 new"), the tile's smaller size, the one over a photo,
    # and the pressable one that is a link.
    class NoteMarkerComponentPreview < ViewComponent::Preview
      def read = render(Admin::Ui::NoteMarkerComponent.new(count: 2, label: "2 open notes"))

      def unread = render(Admin::Ui::NoteMarkerComponent.new(count: 3, label: "3 open notes, new for you", unread: true))

      def small = render(Admin::Ui::NoteMarkerComponent.new(count: 2, label: "2 open notes", size: :small))

      def on_image
        render_with_template(template: "admin/ui/note_marker_component_preview/on_image")
      end

      def link = render(Admin::Ui::NoteMarkerComponent.new(count: 1, label: "1 open note", href: "#"))
    end
  end
end
