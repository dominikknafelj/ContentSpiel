module BlockTypes
  # A visitor's form placed on a page. The form itself is its own record,
  # `Forms::Form` (not `Form`, so this module shadows nothing), built on the
  # Forms screen and reusable on many pages; the block only names it.
  #
  # WHERE EACH VALUE LIVES. The block's one value is the form's id, the same
  # in every language: a setting (`form_id`, the `:form` field type, a String
  # of digits, which `Forms::Placements` compares with `settings ->>
  # 'form_id'`). So no column, no migration and no service. Nothing is
  # required: the picker makes an empty block first, and the public
  # component draws nothing until a kept form with a field is chosen.
  # Everything the form says (its fields, its submit label, its thank-you)
  # is the form's, in its languages, read from its rows when the page is
  # drawn: a form has no published copy and is live at its Save, which moves the public content version, so the page's ETag
  # follows it.
  #
  # Placing a form needs only the right to edit the page, and the select
  # lists every kept form by name (`Admin::Fields::FormField`).
  module Form
    # The block's tile in a section: the form's name, or why there is none.
    # Read from the rows, as CS Studio reads them.
    def self.summary(block, locale:)
      id = block.settings.to_h["form_id"].presence
      return [ [ :hint, :no_form ] ] unless id

      name = ::Forms::Form.kept.where(id: id).pick(:name)
      name ? [ [ :text, name ] ] : [ [ :hint, :gone ] ]
    end

    def self.register
      BlockTypes.register :form do |t|
        t.label "Form"
        t.icon "clipboard_list", family: :form
        t.field :form_id, :form
        t.component Blocks::FormComponent
        # `form_name` the editor's name for the form (shown to nobody by the
        # default template); `fields` the form's fields as a visitor's form
        # draws them (`Forms::PublicField`, ids unique to this block);
        # `action` the endpoint's path; `locale`, `page_id` and `drawn` the
        # three hidden values a send carries (the language, the page, the
        # signed draw time); `honeypot` the hidden field's name;
        # `submit_label` and `thank_you` the form's words in the visitor's
        # language with fallbacks; `unavailable` the line said when the site
        # cannot take answers (no encryption keys), else nil; `string(key)` one of the CMS's six words.
        # The markup the `form-send` script asks of any template is in
        # docs/reference/theming.md, "The Form block".
        t.theme_methods :block, :page, :form_name, :fields, :action, :locale, :page_id, :drawn, :honeypot,
                        :submit_label, :thank_you, :unavailable, :string
        # From the base tokens in `tokens.css`, re-valued by a strong band
        # in `sections.css`; their values are what the contrast test holds
        # (test/integration/design_tokens_test.rb).
        t.tokens themed: %w[form-field-ground form-field-line form-field-focus form-error form-done-ground form-done-line]
        t.stylesheet "form.css"
        t.summary ->(block, locale:) { Form.summary(block, locale: locale) }
        # The shared tests make a form of one required short text, "Your
        # name", and name it (test/support/block_samples.rb); "Send" is the
        # CMS's submit word, the form having none of its own.
        t.sample settings: {}, form: true, shows: [ "Your name", "Send" ]
      end
    end
  end
end
