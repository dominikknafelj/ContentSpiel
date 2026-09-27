require "test_helper"

# Regression net for every Lookbook preview (open-types spec §5): a preview
# that raises when Lookbook tries to render it is broken for every editor
# who opens it, not just the one who happened to click it by hand. This
# iterates every preview class (`ViewComponent::Preview.all`) and every
# example it defines, and renders each one through `render_preview` -- the
# same controller-driven path (`ComponentPreviewsController`) Lookbook itself
# uses -- so a broken preview fails `bin/rails test`, not "whoever next
# opened Lookbook".
class ComponentPreviewsTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "every Lookbook preview renders its examples without raising" do
    previews = ViewComponent::Preview.all
    assert previews.any?, "expected at least one Lookbook preview to be registered"

    previews.each do |preview_class|
      examples = preview_class.examples
      assert examples.any?, "#{preview_class} has no examples"

      examples.each do |example_name|
        render_preview(example_name, from: preview_class)
      rescue => error
        flunk("#{preview_class}##{example_name} raised #{error.class}: #{error.message}")
      end
    end
  end
end
