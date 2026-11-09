module Admin
  module NotesScreen
    # What the Notes screen's two kinds of row share (`InboxRowComponent`, a
    # delivery; `OpenThreadRowComponent`, a record with open threads): the
    # chip that stands for a kind of record and this request's URL options for
    # the link into its notes.
    module RecordRow
      # The module whose chip stands for each kind of record: the chip is the
      # sidebar's own (`StudioModules`), read from the registry so the two
      # cannot differ.
      MODULES = { "page" => :pages, "post" => :posts, "media" => :media }.freeze

      private

      def record_chip(kind)
        entry = StudioModules.find(MODULES.fetch(kind))
        render Admin::Ui::IconChipComponent.new(icon: entry.icon, family: entry.family, size: :xsmall)
      end

      # `admin_url_options` is a controller helper, absent when a component
      # is rendered on its own (a component test).
      def url_options = helpers.respond_to?(:admin_url_options) ? helpers.admin_url_options : {}
    end
  end
end
