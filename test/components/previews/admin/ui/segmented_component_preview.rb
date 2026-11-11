module Admin
  module Ui
    # `Admin::Ui::SegmentedComponent`: links with counts (the Trash screen's
    # types), radios with counts and a 0 (the media library's segments), radios
    # with no counts under a visible legend (a choice field), the media
    # segments wrapping in a narrow box, and a choice with a disabled segment.
    class SegmentedComponentPreview < ViewComponent::Preview
      def links
        render(Admin::Ui::SegmentedComponent.new(mode: :links, label: "Filter by type", segments: [
          { label: "All", href: "#", current: true, count: 7 }, { label: "Pages", href: "#", count: 2 },
          { label: "Posts", href: "#", count: 5 }, { label: "Images", href: "#", count: 0 }
        ]))
      end

      def radios
        render(Admin::Ui::SegmentedComponent.new(mode: :radios, name: :preview_filter, label: "Show", segments: media_segments))
      end

      def no_counts
        render(Admin::Ui::SegmentedComponent.new(mode: :radios, name: :preview_kind, label: "Kind", legend: :visible, segments: [
          { label: "Info", value: "info", id: "preview-kind-info", current: true }, { label: "Tip", value: "tip", id: "preview-kind-tip" },
          { label: "Warning", value: "warning", id: "preview-kind-warning" }
        ]))
      end

      # The media library's five segments in a 240px box: whole segments wrap
      # onto a second row of the track, nothing scrolls sideways.
      def narrow
        render_with_template(locals: { segments: media_segments(prefix: "preview-narrow") })
      end

      def disabled
        render(Admin::Ui::SegmentedComponent.new(mode: :radios, name: :preview_format, label: "Format", legend: :visible, segments: [
          { label: "WebP", value: "webp", id: "preview-format-webp", current: true }, { label: "AVIF", value: "avif", id: "preview-format-avif", disabled: true }
        ]))
      end

      private

      def media_segments(prefix: "preview-filter")
        [ [ "", "All", 128 ], [ "unused", "Unused", 12 ], [ "missing_alt", "Missing alt", 0 ], [ "untranslated", "Untranslated", 4 ], [ "mine", "Mine", 31 ] ]
          .map { |value, label, count| { label:, value:, count:, id: "#{prefix}-#{value.presence || "all"}", current: value.empty? } }
      end
    end
  end
end
