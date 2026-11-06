require "test_helper"

class Admin::RefusalStatusTest < ActiveSupport::TestCase
  def result(denied:) = ApplicationService::Result.new(record: nil, errors: [ "No" ], denied: denied)

  test "a denial is 403 and any other refusal 422" do
    assert_equal :forbidden, Admin::RefusalStatus.for(result(denied: true))
    assert_equal :unprocessable_entity, Admin::RefusalStatus.for(result(denied: false))
  end

  # Every place that answers a refusal asks the one rule: no controller keeps a copy of it.
  test "the autosave forms, the block answers and the notes all answer a refusal through it" do
    sources = %w[app/controllers/concerns/admin/autosave_responses.rb app/controllers/admin/answers/block_refused.rb
      app/controllers/concerns/admin/note_container.rb].map { |path| Rails.root.join(path).read }
    sources.each { |source| assert_includes source, "Admin::RefusalStatus.for(result)" }

    copies = Dir[Rails.root.join("app/controllers/**/*.rb")].select { |path| File.read(path).match?(/denied\?\s*\?\s*:forbidden\s*:\s*:unprocessable_entity/) }
    assert_equal [ Rails.root.join("app/controllers/concerns/admin/refusal_status.rb").to_s ], copies
  end
end
