module Admin
  module EditorScreen
    # The sentences `admin--editor--new-record` writes as the person types: the
    # URL line, a type no page lists, and the New page note that names the
    # chosen parent. Its one list, handed over by both dialogs
    # (`data-messages="<%= messages_data(*NewRecordMessages::KEYS) %>"`), so
    # neither dialog reads the other's constant and the script finds the same
    # keys whichever dialog it runs in.
    module NewRecordMessages
      KEYS = %w[
        components.editor_screen.new_record.url
        components.editor_screen.new_record.not_listed
        components.editor_screen.new_record.page_note
      ].freeze
    end
  end
end
