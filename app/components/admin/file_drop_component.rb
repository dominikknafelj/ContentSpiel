module Admin
  # A drop zone around a visually hidden file input (design pass spec §4): a
  # dashed box saying "Drop an image here or", a "Choose file" button that is
  # really the input's `<label>` (so it works with no JavaScript at all and
  # keyboard focus on the hidden input lights the button through `peer`), and
  # a polite live region echoing the chosen file name(s).
  #
  # The behaviour is `admin--file-drop` (drag highlight, drop -> assign files to
  # the input and fire `change`, name echo). It lives under `controllers/admin/`,
  # so it only loads on CS Studio pages; on the setup wizard (the `application`
  # entry only) the zone degrades to a plain labelled file input: the label
  # still opens the file dialog and the form submits the chosen file, but
  # nothing highlights on drag and the chosen name isn't echoed.
  #
  # Whoever owns the upload (the media library's `admin--media-upload`) listens
  # to the input's own `change`; this component never uploads anything.
  class FileDropComponent < AdminComponent
    def initialize(name:, id:, accept: Media::Asset::ALLOWED_CONTENT_TYPES.join(","), multiple: false, hint: nil, **input_html)
      @name = name
      @id = id
      @accept = accept
      @multiple = multiple
      @hint = hint
      @input_html = input_html
    end

    private

    attr_reader :name, :id, :accept, :multiple, :hint, :input_html

    def input_attrs
      {
        type: "file", name: name, id: id, accept: accept, multiple: multiple,
        class: "peer sr-only",
        data: { "admin--file-drop-target": "input" },
        aria: { describedby: (hint_id if hint) }.compact
      }.merge(input_html) { |_key, ours, theirs| ours.is_a?(Hash) ? ours.merge(theirs) : theirs }
    end

    def hint_id = "#{id}-hint"
  end
end
