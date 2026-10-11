# What stands at the named places of CS Studio's screens (`Admin::Slots`).
# Inside `to_prepare`, like every registry (`config/initializers/types.rb`):
# it runs at boot and after each development reload, when the components are
# new classes; the slots are emptied first, so nothing is registered twice.
Rails.application.config.to_prepare do
  Admin::Slots.reset!

  # Who else has the record open: first in an editor's action row, and at the
  # right end of the image panel's file-name row, each at its own size.
  Admin::Slots.register "editor.header.people", Admin::PresenceScreen::PeopleComponent, size: :header
  Admin::Slots.register "media.panel.header", Admin::PresenceScreen::PeopleComponent, size: :panel

  Admin::Slots.register "editor.header.actions", Admin::NotesScreen::HeaderButtonComponent
  Admin::Slots.register "media.panel.sections", Admin::NotesScreen::MediaSectionComponent

  # The lists' rows: the pill's loader reads each list's counts once for all rows.
  Admin::Slots.register "tree.row.markers", Admin::NotesScreen::RowPillComponent, loader: Admin::NotesScreen::RowPillComponent.loader("Page")
  Admin::Slots.register "posts.row.markers", Admin::NotesScreen::RowPillComponent, loader: Admin::NotesScreen::RowPillComponent.loader("Post")

  # Where someone else is working: last among a tree row's markers, and on a
  # posts row's title line, inside the row's link (`joined`). Each list's
  # people are read once for all its rows.
  Admin::Slots.register "tree.row.markers", Admin::PresenceScreen::RowMarkerComponent, loader: Admin::PresenceScreen::RowMarkerComponent.loader("page")
  Admin::Slots.register "posts.row.title", Admin::PresenceScreen::RowMarkerComponent, loader: Admin::PresenceScreen::RowMarkerComponent.loader("post"), joined: true

  # On a block: who is changing it, then its notes marker. The avatar draws on
  # a section's tile only (a card has the hold strip); it is first, so it
  # stands before the marker (live-editing handoff 4). The editors hand the
  # page's holds through, so its loader reads nothing there.
  Admin::Slots.register "editor.block.markers", Admin::EditorScreen::HolderAvatarComponent, loader: Admin::EditorScreen::HolderAvatarComponent.loader
  Admin::Slots.register "editor.block.markers", Admin::NotesScreen::MarkerComponent
end
