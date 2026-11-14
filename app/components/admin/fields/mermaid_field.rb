module Admin
  module Fields
    # A Diagram block's Mermaid source (Diagram block spec §7, the Design
    # System's EditorDiagramBlock and EditorDiagramError), for `:mermaid`
    # fields: the Code field's textarea (its attributes, its CSS-only height,
    # Tab leaving it, and its counter from nine tenths of the limit) beside
    # the preview, all on one controller, `admin--diagram--preview`.
    #
    # WHAT THE SERVER DRAWS AND WHAT THE SCRIPT DOES. The controller and
    # its values stand on the field's wrapper, `Ui::FieldComponent`'s
    # `.admin-field` (`field_data`), so that one controller holds the source,
    # the preview and the hidden drawing's id wherever the preview stands.
    # The server draws the parts empty and the script fills them: it builds
    # the renderer frame (an `<iframe sandbox="allow-scripts">` at
    # `renderer-url`) into the `frameSlot`, posts the source to it, writes a
    # drawing that worked into the hidden `:diagram_drawing` input
    # (`drawing-field`, its id) and the error, once per new error, into
    # `status`, the polite live region. It reads the line rules from `rules`
    # (`Diagram::Source.rules_json`) and the theme's colours from the
    # `colourProbe`, an empty element of the public diagram's class that
    # nobody sees or hears. Opening a card draws the preview and writes
    # nothing.
    #
    # A TRANSLATION'S STARTING SOURCE. On a translation tab whose
    # language has no source of its own, the textarea shows the original's
    # source as starting text, not as the stored value: it is drawn with no
    # `name`, so no save carries it, and `starting` is true, with a help line
    # saying so (also in a form someone else holds, so the original never
    # reads as this language's own). The script names it (`source-name`) at
    # the first `input`, and names the drawing input (`drawing-name`) before
    # it writes a drawing. Until then the language keeps no source and the
    # site shows the default's diagram.
    #
    # THE LAYOUT. Off a translation tab the source and the preview are two
    # equal columns while the field is at least 40rem wide and stacked below
    # that, the preview under the source: a wrapping row of two 19.5rem
    # halves (`.admin-mermaid-field__pair`), not a container query, because
    # no size container may stand inside the post form
    # (`test/lib/admin_design_rules_test.rb`, "nothing the post form draws is
    # a size container"), and this file is one of its sources. On a
    # translation tab the source and the original take the pair, so the
    # preview stands under the whole pair (`below_pair`).
    #
    # THE SENTENCES of a refused line, of a type off the list and of a first
    # line that names none are the server's own (`errors.messages.diagram_*`,
    # `SENTENCES`), handed to the script under this field's keys, so the
    # card says before a save what a refused save says.
    class MermaidField < CodeField
      CONTROLLER = "admin--diagram--preview".freeze

      # The card's words the script shows, under `admin.components.fields.mermaid_field`.
      MESSAGES = %w[count over frame_title empty drawing no_description error_lead kept nothing_yet kept_badge]
        .map { |key| "components.fields.mermaid_field.#{key}" }.freeze

      # This field's script key => the `errors.messages` key whose sentence it is.
      SENTENCES = {
        "refused.colours" => "diagram_colours",
        "refused.links" => "diagram_links",
        "refused.directive" => "diagram_directive",
        "refused.front_matter" => "diagram_front_matter",
        "refused.maths" => "diagram_maths",
        "unsupported" => "diagram_unsupported",
        "no_type" => "diagram_no_type"
      }.freeze

      # The source's own limit holds without a `max:` (`:mermaid`'s validation).
      def limit = [ field.options[:max], Diagram::Source::MAX_CHARACTERS ].compact.min

      # The original's source shown in a language that has none of its own.
      def starting? = value.blank? && original.present?

      def shown = starting? ? original : value

      def used = shown.to_s.length

      def starting_id = "#{input_id}-starting"

      def starting_text = t(".starting", language: ::Locales.name(::Locales.default, native: true))

      def described_by = [ (counter_id if counter_shown?), (starting_id if starting?) ].compact.join(" ").presence

      def source_name = (input_name unless starting?)

      def drawing = field.options[:drawing].to_s

      # The source beside its original on a translation tab: the preview
      # then stands under the pair, not beside the source.
      def paired? = original.present? && self.class.reference?(field)

      # The controller, on the field's wrapper (see the class comment).
      def field_data
        {
          controller: CONTROLLER,
          "#{CONTROLLER}-renderer-url-value": helpers.admin_diagram_renderer_path,
          "#{CONTROLLER}-rules-value": Diagram::Source.rules_json,
          "#{CONTROLLER}-drawing-field-value": "#{id_prefix}-#{drawing}",
          "#{CONTROLLER}-drawing-name-value": "#{form_name}[#{drawing}]",
          "#{CONTROLLER}-source-name-value": input_name,
          "#{CONTROLLER}-starting-value": starting?,
          "#{CONTROLLER}-limit-value": limit,
          "#{CONTROLLER}-from-value": threshold,
          messages: messages
        }
      end

      def input_data = { "#{CONTROLLER}-target": "source" }

      # The empty frame slot and the status line.
      def preview
        tag.div(class: "admin-mermaid-field__preview min-w-0") do
          safe_join([ tag.div(class: "admin-mermaid-field__frame", data: target("frameSlot")), tag.div(aria: { live: "polite" }, data: target("status")) ])
        end
      end

      def below_pair = (tag.div(preview, class: "admin-mermaid-field__below mt-4") if paired?)

      def target(name) = { "#{CONTROLLER}-target": name }

      # `messages_data`'s JSON with the server's sentences added under this
      # field's keys.
      def messages
        served = JSON.parse(messages_data(*MESSAGES))
        SENTENCES.each { |key, error| served["components.fields.mermaid_field.#{key}"] = I18n.t("errors.messages.#{error}", raise: true) }
        served.to_json
      end
    end
  end
end
