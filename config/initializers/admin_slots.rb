# What stands at the named places of CS Studio's screens (`Admin::Slots`).
# Inside `to_prepare`, like every registry (`config/initializers/types.rb`):
# it runs at boot and after each development reload, when the components are
# new classes; the slots are emptied first, so nothing is registered twice.
Rails.application.config.to_prepare do
  Admin::Slots.reset!

  Admin::Slots.register "editor.header.actions", Admin::NotesScreen::HeaderButtonComponent
  Admin::Slots.register "media.panel.sections", Admin::NotesScreen::MediaSectionComponent

  # The lists' rows: the pill's loader reads each list's counts once for all rows.
  Admin::Slots.register "tree.row.markers", Admin::NotesScreen::RowPillComponent, loader: Admin::NotesScreen::RowPillComponent.loader("Page")
  Admin::Slots.register "posts.row.markers", Admin::NotesScreen::RowPillComponent, loader: Admin::NotesScreen::RowPillComponent.loader("Post")
end
