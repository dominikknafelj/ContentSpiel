require "test_helper"

class StudioModulesTest < ActiveSupport::TestCase
  test "the registry holds today's modules in order, each with a label key that exists in English" do
    assert_equal %i[dashboard pages posts media forms translations tags mind_graph trash users groups settings ai_assistant system_status audit_log],
      StudioModules.entries.map(&:name)

    StudioModules.entries.each do |entry|
      assert I18n.exists?("admin.modules.#{entry.name}", :en), "admin.modules.#{entry.name} is missing"
      assert_includes StudioModules.groups, entry.group, "#{entry.name} is in no group"
      assert_includes Admin::Ui::IconChipComponent::FAMILIES.keys, entry.family, "#{entry.name} has no chip family"
    end
    StudioModules.groups.each { |group| assert I18n.exists?("admin.module_groups.#{group}", :en), "admin.module_groups.#{group} is missing" }

    assert_equal %i[content people system], StudioModules.groups
    assert_equal({ posts: :lists, media: :media, forms: :form }, StudioModules.entries.reject { |entry| entry.family == :neutral }.to_h { |entry| [ entry.name, entry.family ] })
    # The first entry is open to everyone: the Pages index falls back to it.
    assert_nil StudioModules.entries.first.permission
    assert_equal %i[dashboard trash], StudioModules.entries.select(&:badge).map(&:name)
    assert StudioModules.entries.find { |entry| entry.name == :translations }.visible
  end

  test "a second module of one name is refused, and a badge for an unknown module is refused" do
    StudioModules.with(StudioModules.entries) do
      error = assert_raises(ArgumentError) { StudioModules.register(:pages, icon: :pages, path: :admin_pages_path, permission: "pages.read", group: :content) }
      assert_match(/pages/, error.message)
      assert_raises(ArgumentError) { StudioModules.badge(:nowhere) { |viewer:| 1 } }
      assert_raises(ArgumentError) { StudioModules.register(:elsewhere, icon: :pages, path: :admin_pages_path, permission: nil, group: :sideways) }
      assert_raises(ArgumentError) { StudioModules.register(:purple, icon: :pages, family: :purple, path: :admin_pages_path, permission: nil, group: :content) }
    end
  end

  test "a module's badge is counted for the viewer it is asked for" do
    StudioModules.with([]) do
      StudioModules.register(:counted, icon: :pages, path: :admin_pages_path, permission: nil, group: :content)
      StudioModules.badge(:counted) { |viewer:| viewer.email_address.length }

      assert_equal users(:one).email_address.length, StudioModules.count(:counted, viewer: users(:one))
      assert_equal users(:two).email_address.length, StudioModules.count(:counted, viewer: users(:two))
    end
    assert_equal 0, StudioModules.count(:pages, viewer: users(:one)), "a module without a badge counts nothing"
  end

  test "a badge is plain unless registered filled, and the Dashboard's is filled" do
    assert_equal :filled, StudioModules.badge_style(:dashboard)
    assert_equal :plain, StudioModules.badge_style(:trash)
    assert_nil StudioModules.badge_style(:pages)
    StudioModules.with(StudioModules.entries) do
      assert_raises(ArgumentError) { StudioModules.badge(:pages, style: :loud) { |viewer:| 1 } }
    end
  end

  test "with puts the registry back" do
    before = StudioModules.entries
    StudioModules.with([]) do
      assert_empty StudioModules.entries
      StudioModules.register(:extra, icon: :pages, path: :admin_pages_path, permission: nil, group: :system)
      assert_equal %i[extra], StudioModules.entries.map(&:name)
    end
    assert_equal before, StudioModules.entries

    assert_raises(RuntimeError) { StudioModules.with([]) { raise "in the block" } }
    assert_equal before, StudioModules.entries
  end

  # The registry names no component; its families are the chip's, the
  # current module's accent apart, which the sidebar draws.
  test "a module's family is one of the icon chip's" do
    assert_equal Admin::Ui::IconChipComponent::FAMILIES.keys - %i[accent], StudioModules::FAMILIES
  end

  test "reset! empties the registry, for the initializer to fill again" do
    StudioModules.with(StudioModules.entries) do
      StudioModules.reset!
      assert_empty StudioModules.entries
    end
    assert_equal 15, StudioModules.entries.size
  end
end
