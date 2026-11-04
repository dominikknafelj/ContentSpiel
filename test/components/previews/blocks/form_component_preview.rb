require_relative "../preview_fixtures"

module Blocks
  # `Blocks::FormComponent`: a form the preview makes, with a field of
  # each of the five types, named by the block as the type's sample's is.
  class FormComponentPreview < ViewComponent::Preview
    FIELDS = [
      { "key" => "f_prevname", "type" => "short_text", "required" => true, "label" => { "en" => "Your name" }, "help" => {}, "settings" => {} },
      { "key" => "f_prevmail", "type" => "email", "required" => true, "label" => { "en" => "Email address" },
        "help" => { "en" => "We answer to this address." }, "settings" => {} },
      { "key" => "f_prevtext", "type" => "long_text", "required" => false, "label" => { "en" => "Message" }, "help" => {}, "settings" => {} },
      { "key" => "f_prevtopc", "type" => "choice", "required" => false, "label" => { "en" => "Topic" }, "help" => {},
        "settings" => { "display" => "radios", "choices" => [ { "key" => "c_prevnews", "label" => { "en" => "News" } }, { "key" => "c_prevoffr", "label" => { "en" => "Offers" } } ] } },
      { "key" => "f_prevokay", "type" => "checkbox", "required" => true, "label" => { "en" => "I agree" }, "help" => {}, "settings" => {} }
    ].freeze

    def default
      page = PreviewFixtures.page(title: "Form preview")
      form = Forms::Form.create!(name: "Preview form #{SecureRandom.hex(4)}", keep_submissions: false, fields: FIELDS)
      block = page.content_blocks.create!(block_type: :form, position: 0, settings: { "form_id" => form.id.to_s })

      render Blocks::FormComponent.new(block: block, page: page)
    end
  end
end
