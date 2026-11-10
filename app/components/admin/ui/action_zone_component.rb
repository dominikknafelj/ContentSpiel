module Admin
  module Ui
    # An instant action after a form: deleting a user, a group, a form or a
    # submission, changing who is an owner, or moving an image to the trash.
    # A section named by its heading, set off from the form above by a `line`
    # rule and no box of its own, saying in words what the action costs, why
    # it can't be taken (`reason`, when given) and the caller's one trigger
    # on the right.
    #
    # - `heading:` is optional. Without one (the media panel, a narrow
    #   column) no heading is drawn, the section is named by `label:`, the
    #   trigger's words, and the trigger stands under the cost line at the
    #   start. `body:` is optional too: with none the zone is the rule and
    #   the trigger. `body_id:` puts an id on the cost line, for a trigger
    #   that is described by it.
    #
    # - The zone stands AFTER the form, never inside it: its dialogs carry
    #   forms of their own and forms don't nest. The dialogs are the caller's,
    #   drawn after the zone.
    # - `pending_lock: true` attaches `admin--saving--pending-lock` to the
    #   section and draws its hidden hint, so while an explicit-save form on
    #   the page has unsaved changes the trigger (the caller's, marked as the
    #   controller's `control` target) is disabled and the hint says why: the
    #   action answers by drawing the screen again, which would throw the
    #   typed changes away.
    # - It draws no outer margin: the space above it is the caller's (a
    #   margin at the call or its column's gap), so the zone looks the same
    #   wherever it stands.
    # - It decides nothing of who may act: the caller draws it or not, and
    #   the service asks again on the request.
    # - Anything else the caller hands it (`data: { zone: … }`, the hook a
    #   test finds it by) goes on the section, a class added to the zone's own.
    class ActionZoneComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A section named by its heading, or by its label when it has none, holding the caller's one trigger; with pending_lock the trigger stays disabled while any explicit-save form on the page holds unsaved changes, with the hint in words.",
        motion: :none,
        content_edges: %i[short long],
        widths: :from_container,
        interface: %i[heading_id heading label body body_id reason pending_lock],
        limits: [
          "Its dialogs are the caller's, drawn after it, outside every form.",
          "It is named by its heading or, with none, by its label; never by neither.",
          "It decides nothing of who may act: the caller draws it or not."
        ],
        states: %i[rest reason locked headless],
        keys: [],
        slots: %i[trigger],
        controller: "admin--saving--pending-lock",
        keyboard: [ "test/system/admin/users_test.rb", "with a typed change the owner and delete buttons are disabled with the hint, and come back when it is undone" ]
      )

      CLASS = "admin-action-zone flex flex-wrap items-center justify-between gap-3 border-t border-line pt-4".freeze
      HEADLESS_CLASS = "admin-action-zone flex flex-col items-start gap-2 border-t border-line pt-4".freeze

      renders_one :trigger

      def initialize(heading_id: nil, heading: nil, label: nil, body: nil, body_id: nil, reason: nil, pending_lock: false, **html)
        raise ArgumentError, "an action zone is named by a heading with its heading_id, or by a label" unless heading ? heading_id : label

        @heading_id = heading_id
        @heading = heading
        @label = label
        @body = body
        @body_id = body_id
        @reason = reason
        @pending_lock = pending_lock
        @html = html
      end

      private

      attr_reader :heading_id, :heading, :body, :body_id, :reason, :pending_lock

      def words? = body.present? || reason.present? || pending_lock

      def section_attributes
        data = @html.fetch(:data, {})
        data = data.merge(controller: "admin--saving--pending-lock") if pending_lock
        aria = heading ? { labelledby: heading_id } : { label: @label }
        @html.merge(class: [ heading ? CLASS : HEADLESS_CLASS, @html[:class] ].compact.join(" "), aria: aria, data: data)
      end
    end
  end
end
