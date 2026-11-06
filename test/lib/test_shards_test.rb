require "test_helper"
require "tmpdir"

load Rails.root.join("bin/test-shard").to_s

# CI runs both suites as several jobs side by side, each taking one shard of the
# files (`bin/test-shard`, `.github/workflows/ci.yml`): the browser suite as
# four, the unit suite (every test file outside test/system/) as two. A file
# that fell out of every shard would simply never run in CI, and nothing would
# say so: so every test file of either suite is in exactly one shard, at the
# number of shards the workflow asks for and at any other.
class TestShardsTest < ActiveSupport::TestCase
  WORKFLOW = Rails.root.join(".github/workflows/ci.yml")

  def all_files(glob)
    Dir[Rails.root.join(glob)].map { |path| Pathname(path).relative_path_from(Rails.root).to_s }.sort
  end

  test "every system test file is in exactly one shard, however many shards there are" do
    all = all_files("test/system/**/*_test.rb")
    assert_operator all.size, :>, 50

    [ 1, 2, 3, 4, 5, 8 ].each do |total|
      shards = TestShard.shards("system", total, Rails.root.to_s)
      assert_equal total, shards.size
      assert_equal all, shards.flatten.sort, "with #{total} shards"
    end
  end

  test "every unit test file, which is every test file outside test/system, is in exactly one shard, however many shards there are" do
    all = all_files("test/**/*_test.rb").reject { |path| path.start_with?("test/system/") }
    assert_operator all.size, :>, 200
    assert_includes all, "test/lib/test_shards_test.rb"

    [ 1, 2, 3, 5 ].each do |total|
      shards = TestShard.shards("unit", total, Rails.root.to_s)
      assert_equal total, shards.size
      assert_equal all, shards.flatten.sort, "with #{total} shards"
      assert_empty shards.flatten.grep(%r{\Atest/system/})
    end
  end

  # One file can be heavier than a fair share (the mind graph's is a third of
  # the browser suite), and then its shard is that file alone: so the limit is
  # the larger of that file and a fair share with some slack.
  { "system" => 4, "unit" => 2 }.each do |suite, total|
    test "no #{suite} shard is much heavier than a fair share" do
      weights = TestShard.weights(suite, Rails.root.to_s)
      loads = TestShard.shards(suite, total, Rails.root.to_s).map { |files| files.sum { |path| weights.fetch(path) } }
      limit = [ weights.values.max, weights.values.sum / total * 1.15 ].max

      assert_operator loads.max, :<=, limit, "#{suite} shard seconds: #{loads.map(&:round).inspect}"
    end
  end

  # The table is allowed to go stale: a file it does not know is weighed by its
  # tests, and an entry for a file that is gone is simply not used.
  test "a file the table does not know, and an entry for a file that is gone, break nothing" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "test/system"))
      File.write(File.join(root, "test/system/known_test.rb"), "test \"a\" do\nend\n")
      File.write(File.join(root, "test/system/new_test.rb"), "test \"a\" do\nend\ntest \"b\" do\nend\n")
      File.write(File.join(root, "test/system_test_seconds.yml"), "test/system/known_test.rb: 10\ntest/system/gone_test.rb: 99\n")

      assert_equal({ "test/system/known_test.rb" => 10.0, "test/system/new_test.rb" => 20.0 }, TestShard.weights("system", root))
      assert_equal %w[test/system/known_test.rb test/system/new_test.rb], TestShard.shards("system", 2, root).flatten.sort
    end
  end

  # The unit suite's files are those outside test/system, whatever else is in
  # test/ (a helper that is no *_test.rb is no file of either).
  test "the unit suite leaves the browser tests out and counts def test_ methods" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "test/system"))
      FileUtils.mkdir_p(File.join(root, "test/models"))
      File.write(File.join(root, "test/system/browser_test.rb"), "test \"a\" do\nend\n")
      File.write(File.join(root, "test/models/a_test.rb"), "def test_one\nend\ndef test_two\nend\n")
      File.write(File.join(root, "test/unit_test_seconds.yml"), "{}\n")

      assert_equal %w[test/models/a_test.rb], TestShard.files("unit", root)
      assert_equal({ "test/models/a_test.rb" => 2.0 }, TestShard.weights("unit", root))
    end
  end

  test "each suite's workflow shard list and its total agree" do
    jobs = YAML.load_file(WORKFLOW).fetch("jobs")

    { "system-test-shard" => "system", "test-shard" => "unit" }.each do |name, suite|
      job = jobs.fetch(name)
      shards = job.fetch("strategy").fetch("matrix").fetch("shard")
      command = job.fetch("steps").filter_map { |step| step["run"] }.join("\n")

      assert_equal (0...shards.size).to_a, shards, name
      assert_includes command, "bin/test-shard #{suite} ${{ matrix.shard }} #{shards.size}", name
    end
  end

  # The required check is named `test` (the main branch's ruleset), and it must
  # speak for every unit shard; bin/theme-build-check runs in one place only.
  test "the check named test needs the unit shards, and the theme build check runs once" do
    jobs = YAML.load_file(WORKFLOW).fetch("jobs")

    assert_includes Array(jobs.fetch("test").fetch("needs")), "test-shard"

    runs = jobs.values.flat_map { |job| job.fetch("steps", []).filter_map { |step| step["run"] } }
    assert_equal 1, runs.count { |run| run.include?("bin/theme-build-check") }
  end
end
