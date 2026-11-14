module Admin
  module DiagramDrawingsScreen
    # The Draw diagrams screen (`Admin::DiagramDrawingsController#index`; the
    # Design System's StudioDrawDiagrams), whole: the root of the run's
    # controller, `admin--diagram--draw-all`, so that every part it writes
    # stands inside it. In order: the head (`RunHeadComponent`), the "can't
    # draw here" notice, the end-of-run card (`PublishCardComponent`) and
    # the list's one card, its pages' groups (`PageGroupComponent`, in
    # `Diagrams::ToDraw#pages`' order) or the empty line.
    #
    # THE ROOT'S VALUES. `renderer-url`, the renderer frame's address, and
    # `colours`, the `--th-diagram-*` names the script reads off the colour
    # probe (an empty element of the public diagram's class nobody sees or
    # hears) and posts to the frame: both as the Diagram card passes them
    # (`Admin::Fields::MermaidField`), so the screen's drawing is the card's.
    # `start-class` and `stop-class`, the one button's two looks (the
    # primary "Draw all", the secondary "Stop"), as `ButtonComponent` draws
    # them, since the script swaps them in place.
    # `data-messages` holds every word the script shows (`MESSAGES`), with
    # the field's refusal of a drawing (`SENTENCES`), whose words are not
    # CS Studio's own.
    #
    # WHAT THE SCRIPT CLONES. A row's run states (Waiting, Drawing…, Drawn,
    # Doesn't draw, Skipped) are `chip` templates, one per state
    # (`data-state`), drawn by the server so no chip is built by the script;
    # the summary's ok notice is the `summaryNotice` template, with no role
    # of its own, since the live region speaks the summary.
    #
    # Over plain HTTP to a host other than localhost (no `crypto.subtle`) the
    # script shows the warn notice (`insecure`, a note, drawn hidden) and
    # disables "Draw all"; the list still shows and every row still opens.
    class ListComponent < Admin::AdminComponent
      CONTROLLER = RowComponent::CONTROLLER

      # The words the script shows, as `messages_data` serves them.
      MESSAGES = [
        *%w[draw_all stop stopping progress started insecure insecure_short
            summary.drawn summary.failed summary.skipped summary.separator summary.end summary.none failed_generic]
          .map { |key| "diagram_drawings.index.#{key}" },
        *%w[waiting drawing drawn failed skipped].map { |state| "components.diagram_drawings_screen.row.states.#{state}" },
        *%w[does_not_draw changed held stopped gone].map { |reason| "components.diagram_drawings_screen.row.reasons.#{reason}" },
        "components.fields.mermaid_field.too_large",
        "components.fields.mermaid_field.frame_title",
        "components.editor_screen.hold_strip.refused.unknown"
      ].freeze

      # The script's key => the I18n key whose string it is handed: the
      # field's own refusal of a drawing (`:diagram_drawing`).
      SENTENCES = { "components.diagram_drawings_screen.row.reasons.invalid_drawing" => "errors.messages.invalid_drawing" }.freeze

      # The run's states a row's chip takes, with the tone of each; Drawing…
      # has the spinner where the others have the dot.
      RUN_STATES = { waiting: :off, drawing: :off, drawn: :ok, failed: :danger, skipped: :off }.freeze

      def initialize(to_draw:)
        @to_draw = to_draw
      end

      def groups = @to_draw.pages

      def count = @to_draw.count

      def language_column? = ::Locales.enabled.many?

      def target(name) = { "#{CONTROLLER}-target": name }

      def root_data
        {
          controller: CONTROLLER,
          "#{CONTROLLER}-renderer-url-value": helpers.admin_diagram_renderer_path,
          "#{CONTROLLER}-colours-value": Admin::Fields::MermaidField.colour_names.to_json,
          "#{CONTROLLER}-start-class-value": Admin::Ui::ButtonComponent.classes(:primary),
          "#{CONTROLLER}-stop-class-value": Admin::Ui::ButtonComponent.classes(:secondary),
          messages: messages
        }
      end

      # `messages_data`'s JSON with the field's sentences added under this
      # screen's keys.
      def messages
        served = JSON.parse(messages_data(*MESSAGES))
        SENTENCES.each { |key, sentence| served[key] = I18n.t(sentence, raise: true) }
        served.to_json
      end

      def state_word(state) = t("admin.components.diagram_drawings_screen.row.states.#{state}")

      # The chip of a run's state, as `StateChipComponent` draws its tone;
      # Drawing… keeps the off look with the spinner in the dot's place.
      def run_chip(state, tone)
        return render(Admin::Ui::StateChipComponent.new(tone: tone, label: state_word(state))) unless state == :drawing

        chip = Admin::Ui::StateChipComponent
        tag.span(class: "#{chip::CLASS} #{chip::GROUNDS.fetch(:off)}", data: { state_tone: "off" }) do
          safe_join([ tag.span(class: "admin-spinner", aria: { hidden: true }), state_word(state) ])
        end
      end

      def chip_templates
        safe_join(RUN_STATES.map { |state, tone| tag.template(run_chip(state, tone), data: { **target("chip"), state: state }) })
      end

      # The ok notice the script fills with the summary: `NoticeComponent`
      # draws nothing without words, so the box takes its classes.
      def summary_template
        tag.template(tag.div(class: Admin::Ui::NoticeComponent.classes(:ok)), data: target("summaryNotice"))
      end

      def insecure_notice
        render(Admin::Ui::NoticeComponent.new(tone: :warn, role: "note", hidden: true, data: target("insecure"))) do
          t("admin.diagram_drawings.index.insecure")
        end
      end

      def empty_state = Admin::Ui::EmptyStateComponent.new(title: t("admin.diagram_drawings.index.empty"))
    end
  end
end
