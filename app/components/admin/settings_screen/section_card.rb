module Admin
  module SettingsScreen
    # What a Settings section hands the shared card frame
    # (`Admin::Ui::SettingsCardComponent`): the frame knows no section, so the
    # section's id, name, icon and family are mapped here.
    module SectionCard
      # The key of a section's name, which the nav says too.
      def self.word_key(section) = "admin.components.settings_screen.sections.#{section.id}"

      # The frame's keywords for `section`, its name read through `view` (the
      # component rendering the card). The section's id is the heading's, so
      # `#mail` is the anchor every link uses.
      def self.options(section, view)
        { heading_id: section.id, heading: view.t(word_key(section)), icon: section.icon, family: section.family }
      end
    end
  end
end
