module Admin
  module NotesScreen
    # What the Notes screen's two kinds of row share (`InboxRowComponent`, a
    # delivery; `OpenThreadRowComponent`, a record with open threads): the
    # chip that stands for a kind of record and this request's URL options for
    # the link into its notes.
    module RecordRow
      private

      # The kind's chip (`Admin::Ui::RecordChipComponent`), the sidebar's own
      # for the record's module; the row's title beside it names the record.
      def record_chip(kind) = render(Admin::Ui::RecordChipComponent.new(kind:))

      # `admin_url_options` is a controller helper, absent when a component
      # is rendered on its own (a component test).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
