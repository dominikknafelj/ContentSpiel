require "test_helper"

# Regression net for every Lookbook preview: a preview that raises when
# Lookbook tries to render it is broken for every editor who opens it, not
# just the one who happened to click it by hand. This iterates every preview
# class (`ViewComponent::Preview.all`) and every example it defines, and
# renders each one through `render_preview`, which dispatches the whole
# `previews` action of `ComponentPreviewsController` as Lookbook does: its
# callbacks run too, `discard_preview_writes` (a savepoint that is always
# rolled back) included, so a preview whose data needs a commit fails here
# as it fails in Lookbook. Every preview that raises is collected and named
# in one failure, so one broken preview does not hide the next.
class ComponentPreviewsTest < ActiveSupport::TestCase
  include ComponentTestHelper

  test "every Lookbook preview renders its examples without raising" do
    # Lookbook runs in development, where test/support is not loaded: a
    # preview that names a test-support module must fail here too.
    support = Object.send(:remove_const, :MediaRenditions)
    previews = ViewComponent::Preview.all
    assert previews.any?, "expected at least one Lookbook preview to be registered"

    broken = []
    previews.each do |preview_class|
      examples = preview_class.examples
      assert examples.any?, "#{preview_class} has no examples"

      examples.each do |example_name|
        render_preview(example_name, from: preview_class)
      rescue => error
        broken << "#{preview_class}##{example_name} raised #{error.class}: #{error.message}"
      end
    end

    assert_empty broken, "#{broken.size} preview example(s) raised:\n#{broken.join("\n")}"
  ensure
    Object.const_set(:MediaRenditions, support) if support
  end
end
