require "test_helper"

# The visitor (`AccessControl::VISITOR`, forms plan decision 8) may send a
# form, which no group, token or user may be given. What keeps that right
# from leaking is who may ACT as the visitor: in the application, the one
# controller that takes a visitor's send (`FormSendsController`, the plan's
# Task 6) and nothing else, so no other door of the site can authorize a
# write as somebody nobody signed in as. The visitor's other guard is
# test/models/access_control/visitor_test.rb (every key on every channel).
#
# A source grep, comments stripped: it does not see the constant reached
# another way (`const_get`, a variable handed in), and it reads a test's
# name of the constant only to keep the tests that act as a visitor to the
# ones about the visitor.
class VisitorActorTest < ActiveSupport::TestCase
  VISITOR = /\bAccessControl::VISITOR\b|(?<![:\w])VISITOR\b/

  # Where the constant is defined, not used.
  DEFINITION = "app/models/access_control.rb"

  APP_NAMERS = %w[app/controllers/form_sends_controller.rb].freeze

  TEST_NAMERS = %w[
    test/lib/visitor_actor_test.rb
    test/models/access_control/visitor_test.rb
    test/services/forms/submit_test.rb
  ].freeze

  def namers(*roots)
    roots.flat_map { |root| Rails.root.glob("#{root}/**/*.{rb,erb}") }.filter_map do |path|
      code = path.read.lines.reject { |line| line.strip.start_with?("#", "<%#") }.join
      path.to_s.delete_prefix("#{Rails.root}/") if code.match?(VISITOR)
    end.sort
  end

  test "only FormSendsController and Forms::Submit's tests name AccessControl::VISITOR" do
    app = namers("app", "lib") - [ DEFINITION ]
    assert_empty app - APP_NAMERS, "only the endpoint that takes a visitor's send acts as the visitor"

    tests = namers("test")
    assert_empty tests - TEST_NAMERS, "a test that acts as the visitor is about the visitor or the send"
  end

  test "the definition is where the guard looks for it" do
    assert_includes namers("app"), DEFINITION
  end
end
