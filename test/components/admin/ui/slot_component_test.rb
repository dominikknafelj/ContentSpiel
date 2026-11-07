require "test_helper"

# `Admin::Ui::SlotComponent`: what features registered at a named place,
# drawn side by side with no markup of its own. The registry and what each
# entry is handed are test/components/admin/slots_test.rb's.
class Admin::Ui::SlotComponentTest < ViewComponent::TestCase
  include ContentHelper

  class MarkComponent < ViewComponent::Base
    def initialize(record:, viewer:, data: nil, **context)
      @record = record
    end

    def call = tag.b("mark #{@record.id}")
  end

  class OtherMarkComponent < MarkComponent
    def call = tag.i("other")
  end

  test "rest: each entry's markup in registration order, with nothing around or between them" do
    page = create_page(title: "About")

    Admin::Slots.with("editor.block.markers" => [ MarkComponent, OtherMarkComponent ]) do
      render_inline Admin::Ui::SlotComponent.new(name: "editor.block.markers", record: page, viewer: users(:one))
    end

    assert_equal "<b>mark #{page.id}</b><i>other</i>", rendered_content
  end

  test "with nothing registered it draws nothing at all" do
    Admin::Slots.with("editor.block.markers" => []) do
      render_inline Admin::Ui::SlotComponent.new(name: "editor.block.markers", record: create_page(title: "About"), viewer: nil)
    end

    assert_equal "", rendered_content
  end
end
