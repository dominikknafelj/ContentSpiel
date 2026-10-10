require "test_helper"

load Rails.root.join("bin/system-test-shard").to_s

# CI runs the browser suite as several jobs side by side, each taking one shard
# of the files (`bin/system-test-shard`, `.github/workflows/ci.yml`). A file
# that fell out of every shard would simply never run in CI, and nothing would
# say so: so every system test file is in exactly one shard, at the number of
# shards the workflow asks for and at any other.
class SystemTestShardsTest < ActiveSupport::TestCase
  WORKFLOW = Rails.root.join(".github/workflows/ci.yml")

  test "every system test file is in exactly one shard, however many shards there are" do
    all = Dir[Rails.root.join("test/system/**/*_test.rb")].map { |path| Pathname(path).relative_path_from(Rails.root).to_s }.sort
    assert_operator all.size, :>, 50

    [ 1, 2, 3, 4, 5, 8 ].each do |total|
      shards = SystemTestShard.shards(total, Rails.root.to_s)
      assert_equal total, shards.size
      assert_equal all, shards.flatten.sort, "with #{total} shards"
    end
  end

  test "the shards hold about the same number of tests" do
    counts = SystemTestShard.shards(4, Rails.root.to_s).map { |files| files.sum { |path| SystemTestShard.tests_in(path, Rails.root.to_s) } }
    assert_operator counts.max - counts.min, :<=, counts.sum / 10, "shard sizes: #{counts.inspect}"
  end

  test "the workflow's shard list and its total agree" do
    workflow = YAML.load_file(WORKFLOW)
    job = workflow.fetch("jobs").fetch("system-test-shard")
    shards = job.fetch("strategy").fetch("matrix").fetch("shard")
    command = job.fetch("steps").filter_map { |step| step["run"] }.join("\n")

    assert_equal (0...shards.size).to_a, shards
    assert_includes command, "bin/system-test-shard ${{ matrix.shard }} #{shards.size}"
  end
end
