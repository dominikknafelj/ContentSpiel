require "test_helper"
require "open3"

# The backend contract is a gem's as much as this suite's: a gem that brings
# a search engine (`ContentSpiel::Plugins.search_backends`) runs it against
# its own backend by requiring the file by path from the ContentSpiel it is
# tested with (test/support/site_search_backend_contract.rb says how). So it
# is run here the way a gem runs it: in a process of its own, started from
# another folder, with the application booted in the test environment and
# nothing of this suite's helpers loaded, against the test backend as the
# gem's own. A helper of test/support named inside the contract, or a
# require it leans on, fails this and nothing else.
class SiteSearchBackendContractTest < ActiveSupport::TestCase
  RUN_SECONDS = 90

  SCRIPT = <<~RUBY.freeze
    ENV["RAILS_ENV"] = "test"
    require File.join(ENV.fetch("CONTENTSPIEL_ROOT"), "config/environment")
    require "active_support/test_case"
    require Rails.root.join("test/support/site_search_backend_contract").to_s
    require Rails.root.join("test/support/site_search_fake").to_s

    class GemBackendContractTest < ActiveSupport::TestCase
      include SiteSearchBackendContract
      include SiteSearchBackendContract::BareDocuments

      def backend = @backend ||= SiteSearch::Fake.new
    end

    exit(Minitest.run(%w[--seed 1]) ? 0 : 1)
  RUBY

  test "a gem's test requires the contract by path and passes it with its own backend" do
    printed, status = Dir.mktmpdir("gem") do |folder|
      Bundler.with_original_env do
        env = { "CONTENTSPIEL_ROOT" => Rails.root.to_s, "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s, "SEARCH_BACKEND" => nil }
        Open3.popen2e(env, RbConfig.ruby, "-e", SCRIPT, chdir: folder) do |input, output, thread|
          input.close
          reader = Thread.new { output.read }
          unless thread.join(RUN_SECONDS)
            Process.kill("KILL", thread.pid)
            thread.join
            flunk "the contract did not finish in #{RUN_SECONDS} seconds"
          end
          [ reader.value, thread.value ]
        end
      end
    end

    assert status.success?, printed
    contract_tests = File.read(Rails.root.join("test/support/site_search_backend_contract.rb")).scan(/^\s+test "contract: /).size
    assert_match(/\b#{contract_tests} runs, \d+ assertions, 0 failures, 0 errors/, printed)
  end
end
