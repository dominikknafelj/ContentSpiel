# Shared setup for ViewComponent tests (open-types spec §5), included
# explicitly per test class rather than globally in test_helper.rb --
# `ViewComponent::TestHelpers` pulls in `Capybara::Minitest::Assertions`,
# whose `page` method would otherwise shadow the one Capybara's own system
# tests (test/system) already rely on.
#
# Every public component calls `page_url_path`/`post_url_path` (via
# `ApplicationComponent`'s `helpers` delegation), which read `public_urls`
# off whichever controller is rendering. `ViewComponent::TestHelpers`'
# own default (`ApplicationController`) has no such method -- only
# `PublicController`/`PreviewController`/`ComponentPreviewsController` do --
# so component tests render through `ComponentPreviewsController`, the same
# controller Lookbook and the preview smoke test use.
module ComponentTestHelper
  extend ActiveSupport::Concern

  included do
    include ViewComponent::TestHelpers
    include Capybara::Minitest::Assertions

    # Defined here, inside `included do`, rather than as a plain instance
    # method on this module: a method `def`ed directly on the including
    # class (which is what a `class_eval`/`included do` block does) always
    # wins over one from an included module, regardless of include order --
    # a method on `ComponentTestHelper` itself would instead lose to
    # `ViewComponent::TestHelpers`' own default (`ApplicationController`),
    # since that module is included *after* this one, one line up.
    def vc_test_controller_class
      ComponentPreviewsController
    end
  end
end
