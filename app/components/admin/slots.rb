module Admin
  # Named places on CS Studio's screens where a feature puts a part of its
  # own (presence spec §4.1). A screen draws `Admin::Ui::SlotComponent` at the
  # place and does not know what stands there; a feature registers a
  # component for the name in `config/initializers/admin_slots.rb`. That is
  # what keeps the editors' header and the media panel free of the features
  # that draw in them (`test/lib/notes_boundary_test.rb`).
  #
  # THE FILE IS HERE and not under `app/models`, where the other registries
  # live, because it holds component CLASSES, and nothing below a component may
  # name one (`test/lib/dependency_direction_test.rb`). `test/lib/
  # source_layout_test.rb` lists it, with the base class, as the only loose file
  # of this folder.
  #
  # A slot component is built as `component.new(record:, viewer:, data:,
  # **context)`:
  # - `record` is the page, post or image the screen is about (for a row of a
  #   list, the row's record);
  # - `viewer` is the user looking (or nil), passed explicitly: a slot
  #   component reads no `Current`;
  # - `data` is, for a LIST slot (a row), what the entry's loader answered for
  #   that record, and nil for a single-record slot, where the component asks
  #   its own question;
  # - `context` is whatever the host handed to the slot (`locale:`,
  #   `url_options:`, and for a screen that has already read something the
  #   feature would read again, that). A component takes the context it uses
  #   and ignores the rest (`**`).
  # `render?` decides whether it draws; one that says no leaves no markup.
  #
  # A list slot's `loader` is called ONCE per render of the list with all its
  # records and the viewer (`Slots.load`), so a row costs no query of its own:
  # `->(records, viewer:) { { record.id => data } }`.
  #
  # RELOADING. This module is autoloaded like the components it holds, so a
  # development reload unloads it with them and the registry starts empty;
  # `config/initializers/admin_slots.rb` fills it again in `to_prepare`
  # (which also runs at boot), after `reset!`, so nothing is registered twice
  # and no class replaced by a reload is kept.
  #
  # Each worker of a parallel test run is its own process; a test that changes
  # a slot does it through `with`, which puts the registry back in an `ensure`.
  module Slots
    Entry = Data.define(:component, :loader)

    NAMES = %w[
      editor.header.people editor.header.actions
      media.panel.header media.panel.sections
      tree.row.markers posts.row.markers
    ].freeze

    @registry = NAMES.to_h { |name| [ name, [] ] }

    class << self
      # Raises for a name no screen draws. Entries keep registration order.
      def register(name, component, loader: nil)
        entries_for!(name) << Entry.new(component:, loader:)
      end

      def entries(name) = entries_for!(name).dup

      # `{ entry => { record id => data } }` for the entries of a LIST slot
      # that have a loader, each called once with every record. An entry
      # without one is not in the hash: its components get `data: nil`.
      def load(name, records, viewer:)
        records = records.to_a
        entries(name).select(&:loader).to_h { |entry| [ entry, entry.loader.call(records, viewer: viewer) ] }
      end

      # Empties every slot, or sets them to `to` (`{ name => [entries] }`).
      # For the initializer and for tests.
      def reset!(to: nil)
        to&.each_key { |name| entries_for!(name) }
        @registry = NAMES.to_h { |name| [ name, (to&.fetch(name, nil) || []).map { |entry| entry_of(entry) } ] }
      end

      # For a test: the given slots hold the given entries (an `Entry` or a
      # component class) for the block, the others as they were, and the
      # registry is put back after it, whatever the block does.
      def with(slots)
        before = @registry.transform_values(&:dup)
        slots.each_key { |name| entries_for!(name) }
        slots.each { |name, entries| @registry[name] = entries.map { |entry| entry_of(entry) } }
        yield
      ensure
        @registry = before
      end

      private

      def entries_for!(name)
        @registry.fetch(name.to_s) { raise ArgumentError, "no slot is named #{name.inspect}; the names are #{NAMES.join(", ")}" }
      end

      def entry_of(entry) = entry.is_a?(Entry) ? entry : Entry.new(component: entry, loader: nil)
    end
  end
end
