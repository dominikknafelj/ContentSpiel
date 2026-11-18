require "test_helper"
require "tmpdir"

class ContentSpiel::Backup::RunningVersionTest < ActiveSupport::TestCase
  RunningVersion = ContentSpiel::Backup::RunningVersion

  setup do
    @root = Pathname(Dir.mktmpdir)
    @path = RunningVersion.path(@root)
  end

  teardown { FileUtils.remove_entry(@root) }

  test "the file is beside the status file, read back whole, its time in UTC" do
    assert_equal @root.join("storage", "backup", "accessory.json"), @path
    written = RunningVersion.new(cms_version: "0.11.0", started_at: Time.utc(2026, 11, 18, 2, 59, 30), every_hours: 6)
    written.write(@path)

    assert_equal written, RunningVersion.read(@path)
    assert_equal({ "cms_version" => "0.11.0", "started_at" => "2026-11-18T02:59:30Z", "every_hours" => 6 }, JSON.parse(@path.read))
    assert_predicate RunningVersion.read(@path).started_at, :utc?
    assert_equal 0o644, @path.stat.mode & 0o777
  end

  test "no file, or one that is not this JSON, reads as nil" do
    assert_nil RunningVersion.read(@path)

    @path.dirname.mkpath
    [ "", "{", "[]", "null", "{}", %({"cms_version": 11, "started_at": "2026-11-18T02:59:30Z"}),
      %({"cms_version": "", "started_at": "2026-11-18T02:59:30Z"}),
      %({"cms_version": "0.11.0", "started_at": "yesterday"}), "\xFF\xFE" ].each do |text|
      @path.binwrite(text)
      assert_nil RunningVersion.read(@path), text.inspect
    end

    @path.write(%({"cms_version": "0.11.0"}))
    assert_equal RunningVersion.new(cms_version: "0.11.0", started_at: nil, every_hours: 24), RunningVersion.read(@path)
  end

  test "every_hours is read when it is one of the cadences, and is 24 when missing or anything else" do
    @path.dirname.mkpath
    [ 1, 2, 3, 4, 6, 8, 12, 24 ].each do |hours|
      @path.write(%({"cms_version": "0.11.0", "every_hours": #{hours}}))
      assert_equal hours, RunningVersion.read(@path).every_hours
    end
    [ "", %(, "every_hours": null), %(, "every_hours": 5), %(, "every_hours": 0), %(, "every_hours": 48),
      %(, "every_hours": "6"), %(, "every_hours": 6.0), %(, "every_hours": -6) ].each do |part|
      @path.write(%({"cms_version": "0.11.0"#{part}}))
      read = RunningVersion.read(@path)
      assert_equal 24, read.every_hours, part.inspect
      assert_equal "0.11.0", read.cms_version, "a cadence it does not know keeps the version"
    end
  end

  test "a reader's cadence is the file's, or 24 with no readable file" do
    assert_equal 6, RunningVersion.every_hours_of(RunningVersion.new(cms_version: "0.11.0", started_at: nil, every_hours: 6))
    assert_equal 24, RunningVersion.every_hours_of(nil)
    assert_equal 24, RunningVersion.every_hours_of(:none)
  end
end
