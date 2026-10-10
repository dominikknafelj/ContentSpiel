module Admin
  module Ui
    # A drop zone around a visually hidden file input (design pass spec §4): a
    # dashed box saying "Drop an image here or", a "Choose file" button that is
    # really the input's `<label>` (so it works with no JavaScript at all and
    # keyboard focus on the hidden input lights the button through `peer`), and
    # a polite live region echoing the chosen file name(s).
    #
    # The behaviour is `file-drop` (drag highlight, drop -> assign files to the
    # input and fire `change`, name echo). It lives in `controllers/`, not
    # `controllers/admin/`, because the setup wizard's logo field uses this zone
    # and loads only the `application` entry: an unwired zone would print "Drop
    # an image here" yet let the browser navigate away on a drop (losing the
    # form). Same reason as `password_field_controller.js`.
    #
    # `label:` is the input's accessible name (aria-label), e.g. "Upload images";
    # without it the visible "Choose file" label names it.
    #
    # Whoever owns the upload (the media library's `admin--media--upload`) listens
    # to the input's own `change`; this component never uploads anything.
    class FileDropComponent < AdminComponent
      def initialize(name:, id:, accept: Media::Asset::ALLOWED_CONTENT_TYPES.join(","), multiple: false, hint: nil, label: nil, **input_html)
        @name = name
        @id = id
        @accept = accept
        @multiple = multiple
        @hint = hint
        @label = label
        @input_html = input_html
      end

      private

      attr_reader :name, :id, :accept, :multiple, :hint, :label, :input_html

      def input_attrs
        {
          type: "file", name: name, id: id, accept: accept, multiple: multiple,
          class: "peer sr-only",
          data: { "file-drop-target": "input" },
          aria: { describedby: (hint_id if hint), label: label }.compact
        }.merge(input_html) { |_key, ours, theirs| ours.is_a?(Hash) ? ours.merge(theirs) : theirs }
      end

      def hint_id = "#{id}-hint"
    end
  end
end
