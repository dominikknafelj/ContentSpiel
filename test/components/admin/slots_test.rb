require "test_helper"

# Screen slots (presence spec §4.1): named places on a screen where a feature
# registers a component, so a core component renders "what stands here"
# without naming the feature.
class Admin::SlotsTest < ViewComponent::TestCase
  include ContentHelper

  # Draws the data it was given and the context it was handed, so a test can
  # read how the slot built it.
  class ProbeComponent < ViewComponent::Base
    def initialize(record:, viewer:, data: nil, **context)
      @record = record
      @viewer = viewer
      @data = data
      @context = context
    end

    def call = tag.i("#{self.class.name.demodulize}:#{@record.id}:#{@viewer&.id}:#{@data.inspect}:#{@context.sort.to_h.inspect}", data: { probe: true })
  end

  class FirstComponent < ProbeComponent; end
  class SecondComponent < ProbeComponent; end

  class QuietComponent < ProbeComponent
    def render? = false
  end

  def entry(component, loader: nil, **options) = Admin::Slots::Entry.new(component:, loader:, options:)

  test "the names a screen may put a slot at" do
    assert_equal %w[editor.header.people editor.header.actions media.panel.header media.panel.sections tree.row.markers posts.row.markers posts.row.title], Admin::Slots::NAMES
  end

  test "an unknown name is refused at registration" do
    error = assert_raises(ArgumentError) { Admin::Slots.register("editor.nowhere", FirstComponent) }
    assert_match(/editor\.nowhere/, error.message)
  end

  test "entries come back in registration order" do
    Admin::Slots.with("media.panel.header" => []) do
      Admin::Slots.register("media.panel.header", SecondComponent)
      Admin::Slots.register("media.panel.header", FirstComponent)

      assert_equal [ SecondComponent, FirstComponent ], Admin::Slots.entries("media.panel.header").map(&:component)
    end
  end

  test "a slot with nothing registered renders nothing at all, not even a wrapper" do
    page = create_page(title: "About")

    Admin::Slots.with("editor.header.people" => []) do
      render_inline Admin::Ui::SlotComponent.new(name: "editor.header.people", record: page, viewer: nil)
    end

    assert_equal "", rendered_content
  end

  test "the entries are drawn in order, each built with the record, the viewer, no data and the host's context" do
    page = create_page(title: "About")
    viewer = users(:one)

    Admin::Slots.with("editor.header.actions" => [ entry(FirstComponent), entry(SecondComponent) ]) do
      render_inline Admin::Ui::SlotComponent.new(name: "editor.header.actions", record: page, viewer: viewer, locale: "de", url_options: { locale: "de" })
    end

    probes = page_nodes = Capybara.string(rendered_content).all("i[data-probe]").map(&:text)
    assert_equal [ "FirstComponent", "SecondComponent" ], page_nodes.map { |text| text.split(":").first }
    assert_equal "FirstComponent:#{page.id}:#{viewer.id}:nil:{locale: \"de\", url_options: {locale: \"de\"}}", probes.first
  end

  test "a list slot hands each entry the data its loader returned for the record" do
    page = create_page(title: "About")
    other = create_page(title: "Other")
    loader = ->(records, viewer:) { records.to_h { |record| [ record.id, "mark #{record.id}" ] } }
    unloaded = entry(SecondComponent)
    loaded_entry = entry(FirstComponent, loader: loader)

    Admin::Slots.with("tree.row.markers" => [ loaded_entry, unloaded ]) do
      loaded = Admin::Slots.load("tree.row.markers", [ page, other ], viewer: users(:one))
      render_inline Admin::Ui::SlotComponent.new(name: "tree.row.markers", record: other, viewer: users(:one), loaded: loaded)
    end

    texts = Capybara.string(rendered_content).all("i[data-probe]").map(&:text)
    assert_equal [ "FirstComponent:#{other.id}:#{users(:one).id}:\"mark #{other.id}\":{}", "SecondComponent:#{other.id}:#{users(:one).id}:nil:{}" ], texts
  end

  test "a registration carries options, which win over the host's context on a clash" do
    page = create_page(title: "About")

    Admin::Slots.with("media.panel.header" => []) do
      Admin::Slots.register("media.panel.header", FirstComponent, size: :panel, locale: "fixed")
      assert_equal({ size: :panel, locale: "fixed" }, Admin::Slots.entries("media.panel.header").first.options)
      render_inline Admin::Ui::SlotComponent.new(name: "media.panel.header", record: page, viewer: nil, locale: "de")
    end

    assert_equal "FirstComponent:#{page.id}::nil:{locale: \"fixed\", size: :panel}", Capybara.string(rendered_content).find("i[data-probe]").text
  end

  test "an option named like one of the slot's own arguments is refused" do
    Admin::Slots.with("media.panel.header" => []) do
      %i[record viewer data component].each do |name|
        assert_raises(ArgumentError, name.to_s) { Admin::Slots.register("media.panel.header", FirstComponent, name => 1) }
      end
      assert_empty Admin::Slots.entries("media.panel.header")
    end
  end

  test "the same component and loader registered twice with different options are two entries, each loaded once" do
    page = create_page(title: "About")
    calls = 0
    loader = ->(records, viewer:) { calls += 1; records.to_h { |record| [ record.id, "data" ] } }

    Admin::Slots.with("tree.row.markers" => []) do
      Admin::Slots.register("tree.row.markers", FirstComponent, loader: loader, size: :header)
      Admin::Slots.register("tree.row.markers", FirstComponent, loader: loader, size: :panel)

      loaded = Admin::Slots.load("tree.row.markers", [ page ], viewer: nil)

      assert_equal 2, loaded.size
      assert_equal 2, calls
      assert_equal [ { size: :header }, { size: :panel } ], loaded.keys.map(&:options)
    end
  end

  test "load calls each loader once with every record and the viewer, and skips entries without one" do
    pages = [ create_page(title: "A"), create_page(title: "B"), create_page(title: "C") ]
    calls = []
    loader = ->(records, viewer:) { calls << [ records, viewer ]; {} }
    first = entry(FirstComponent, loader: loader)
    second = entry(SecondComponent)

    Admin::Slots.with("posts.row.markers" => [ first, second ]) do
      loaded = Admin::Slots.load("posts.row.markers", pages, viewer: users(:one))

      assert_equal [ first ], loaded.keys
    end

    assert_equal [ [ pages, users(:one) ] ], calls
  end

  test "a component whose render? is false leaves no markup" do
    page = create_page(title: "About")

    Admin::Slots.with("editor.header.actions" => [ entry(QuietComponent) ]) do
      render_inline Admin::Ui::SlotComponent.new(name: "editor.header.actions", record: page, viewer: nil)
    end

    assert_equal "", rendered_content
  end

  test "with puts the registry back, whatever the block does" do
    before = Admin::Slots::NAMES.to_h { |name| [ name, Admin::Slots.entries(name) ] }

    assert_raises(RuntimeError) do
      Admin::Slots.with("media.panel.sections" => [ entry(FirstComponent) ], "tree.row.markers" => [ entry(FirstComponent) ]) { raise "boom" }
    end

    assert_equal before, Admin::Slots::NAMES.to_h { |name| [ name, Admin::Slots.entries(name) ] }
  end

  test "the real registry holds notes' components, and presence's people in the header at its size and in the panel at its" do
    assert_equal [ Admin::NotesScreen::HeaderButtonComponent ], Admin::Slots.entries("editor.header.actions").map(&:component)
    assert_equal [ Admin::NotesScreen::MediaSectionComponent ], Admin::Slots.entries("media.panel.sections").map(&:component)
    assert_equal [ Admin::NotesScreen::RowPillComponent ], Admin::Slots.entries("tree.row.markers").map(&:component)
    assert_equal [ Admin::NotesScreen::RowPillComponent ], Admin::Slots.entries("posts.row.markers").map(&:component)
    assert_empty Admin::Slots.entries("posts.row.title")
    assert_equal [ [ Admin::PresenceScreen::PeopleComponent, { size: :header } ] ], Admin::Slots.entries("editor.header.people").map { |entry| [ entry.component, entry.options ] }
    assert_equal [ [ Admin::PresenceScreen::PeopleComponent, { size: :panel } ] ], Admin::Slots.entries("media.panel.header").map { |entry| [ entry.component, entry.options ] }
  end

  test "the initializer can run again, as after a development reload, without registering anything twice" do
    before = Admin::Slots::NAMES.to_h { |name| [ name, Admin::Slots.entries(name) ] }
    shape = -> { Admin::Slots::NAMES.to_h { |name| [ name, Admin::Slots.entries(name).map { |entry| [ entry.component, !entry.loader.nil? ] } ] } }
    expected = shape.call

    block = nil
    config = Rails.application.config
    original = config.method(:to_prepare)
    config.define_singleton_method(:to_prepare) { |&given| block = given }
    begin
      load Rails.root.join("config/initializers/admin_slots.rb").to_s
    ensure
      config.define_singleton_method(:to_prepare, original)
    end
    assert_not_nil block, "the initializer registers inside to_prepare"
    2.times { block.call }

    assert_equal expected, shape.call
  ensure
    Admin::Slots.reset!(to: before)
  end
end
