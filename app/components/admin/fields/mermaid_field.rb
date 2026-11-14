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
    # The server draws the parts empty or hidden and the script fills them:
    # it builds the renderer frame (an `<iframe sandbox="allow-scripts">` at
    # `renderer-url`) into the `frameSlot`, posts the source to it, writes a
    # drawing that worked into the hidden `:diagram_drawing` input
    # (`drawing-field`, its id) and the error, once per new error, into
    # `status`, the polite live region, as a clone of the warn notice in
    # `notice` (a `<template>`, so no box is built by hand). It shows the
    # state's words the slot holds (`blank`, `kept`, `busy`) and marks the
    # source's offending line (`line`). It reads the line rules from `rules`
    # (`Diagrams::Source.rules_json`) and the theme's colours (`colours`, the
    # names) from the `colourProbe`, an empty element of the public diagram's
    # class that nobody sees or hears. Opening a card draws the preview and
    # writes nothing. The counter under the source is the Code field's own
    # script, `admin--editor--code-limit`, on the source's half.
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
    # line that names none are written once, in `errors.messages.diagram_*`
    # (`SENTENCES`), and handed to the script under this field's keys. No
    # save is refused for them: the card says them, the source is stored as
    # typed and the drawing stays the last that worked.
    class MermaidField < CodeField
      CONTROLLER = "admin--diagram--preview".freeze

      # The card's words the script shows, under `admin.components.fields.mermaid_field`.
      MESSAGES = %w[frame_title empty error_lead kept nothing_yet kept_badge too_long too_large]
        .map { |key| "components.fields.mermaid_field.#{key}" }.freeze

      # The server's sentences the script shows: its key => the I18n key
      # whose string it is handed (`messages`). `test/lib/script_messages_test.rb`
      # reads this list as served.
      SENTENCES = {
        "refused.colours" => "diagram_colours",
        "refused.links" => "diagram_links",
        "refused.directive" => "diagram_directive",
        "refused.front_matter" => "diagram_front_matter",
        "refused.maths" => "diagram_maths",
        "unsupported" => "diagram_unsupported",
        "no_type" => "diagram_no_type"
      }.to_h { |key, error| [ "components.fields.mermaid_field.#{key}", "errors.messages.#{error}" ] }.freeze

      # The `--th-diagram-*` tokens the script reads off the colour probe and
      # posts to the frame: the Diagram block's themed tokens, which CS
      # Studio's stylesheet defines on the probe's class from its own.
      def self.colour_names = ::BlockTypes.fetch(:diagram).themed_tokens.map { |name| "--th-#{name}" }

      # The source's own limit holds without a `max:` (`:mermaid`'s validation).
      def limit = [ field.options[:max], Diagrams::Source::MAX_CHARACTERS ].compact.min

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
          "#{CONTROLLER}-rules-value": Diagrams::Source.rules_json,
          "#{CONTROLLER}-drawing-field-value": "#{id_prefix}-#{drawing}",
          "#{CONTROLLER}-drawing-name-value": "#{form_name}[#{drawing}]",
          "#{CONTROLLER}-source-name-value": input_name,
          "#{CONTROLLER}-starting-value": starting?,
          "#{CONTROLLER}-colours-value": self.class.colour_names.to_json,
          "#{CONTROLLER}-description-field-value": description_id,
          messages: messages
        }
      end

      # The source target, the Code field's counter (`admin--editor--code-limit`,
      # on the source's half, `wrapper_data`) and the preview's draw. In a form
      # someone else holds only the counter's read survives (`HeldFields`).
      def input_data
        {
          "#{CONTROLLER}-target": "source",
          "admin--editor--code-limit-target": "input",
          action: "input->admin--editor--code-limit#update input->#{CONTROLLER}#input"
        }
      end

      # The input of the field that describes the drawing (`description:`),
      # whose blank the card points out; nil when the schema names none.
      def description_id = (field.options[:description] && "#{id_prefix}-#{field.options[:description]}")

      # "The site shows this diagram once it has a description.", drawn hidden:
      # the script shows it while the description's input is blank.
      def undescribed_notice
        return unless description_id

        render(Admin::Ui::NoticeComponent.new(tone: :neutral, size: :compact, hidden: true, class: "mt-2", data: target("undescribed"))) { t(".no_description") }
      end

      def kept_badge = render(Admin::Ui::BadgeComponent.new(label: t(".kept_badge"), hidden: true, class: "admin-mermaid-field__kept", data: target("kept")))

      # The warn notice the script clones into `status` for an error, its
      # parts empty: the lead, the sentence, Mermaid's own message and what
      # the site does. Inside the live region it has no role of its own.
      def notice_template
        notice = render(Admin::Ui::NoticeComponent.new(tone: :warn, size: :compact, role: nil)) do
          safe_join([
            tag.strong(class: "block font-semibold", data: { part: "lead" }),
            tag.span(class: "block", data: { part: "sentence" }),
            tag.pre(class: "mt-1.5 font-cs-mono text-xs whitespace-pre-wrap", data: { part: "message" }),
            tag.span(class: "block", data: { part: "site" })
          ])
        end
        tag.template(notice, data: target("notice"))
      end

      # The frame slot, the status line, the description's note and the
      # notice's template. The slot
      # holds the script's renderer frame and, over it, the state's words,
      # each drawn hidden for the script to show: the blank frame's line
      # (`empty`, or `nothing_yet` beside an error), the kept drawing's
      # badge, and "Drawing…", which only the eye needs (`status` speaks the
      # errors alone).
      def preview
        tag.div(class: "admin-mermaid-field__preview min-w-0") do
          safe_join([
            tag.div(class: "admin-mermaid-field__frame", data: target("frameSlot")) do
              safe_join([
                tag.p(class: "admin-mermaid-field__blank text-sm text-meta", hidden: true, data: target("blank")),
                kept_badge,
                tag.span(t(".drawing"), class: "admin-mermaid-field__busy text-label text-meta", hidden: true, aria: { hidden: true }, data: target("busy"))
              ])
            end,
            tag.div(aria: { live: "polite" }, data: target("status")),
            undescribed_notice,
            notice_template
          ])
        end
      end

      def below_pair =(tag.div(preview, class: "admin-mermaid-field__below mt-4") if paired?)

      def target(name) = { "#{CONTROLLER}-target": name }

      # `messages_data`'s JSON with the server's sentences added under this
      # field's keys.
      def messages
        served = JSON.parse(messages_data(*MESSAGES))
        SENTENCES.each { |key, sentence| served[key] = I18n.t(sentence, raise: true) }
        served.to_json
      end
    end
  end
end
