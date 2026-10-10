# What stands at the named places of CS Studio's screens (`Admin::Slots`).
# Inside `to_prepare`, like every registry (`config/initializers/types.rb`):
# it runs at boot and after each development reload, when the components are
# new classes; the slots are emptied first, so nothing is registered twice.
Rails.application.config.to_prepare do
  Admin::Slots.reset!

  Admin::Slots.register "editor.header.actions", Admin::NotesScreen::HeaderButtonComponent
  Admin::Slots.register "media.panel.sections", Admin::NotesScreen::MediaSectionComponent
end
