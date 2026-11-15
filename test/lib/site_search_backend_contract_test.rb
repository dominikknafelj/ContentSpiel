require "test_helper"
require "open3"

# The backend contract is a gem's as much as this suite's: a gem that brings
# a search engine (`ContentSpiel::Plugins.search_backends`) runs it against
# its own backend by requiring the file by path from the ContentSpiel it is
# tested with (test/support/site_search_backend_contract.rb says how). So it
# is run here the way such a gem runs it, in a folder outside `Rails.root`:
#
# - a gem, `acme_search`, with a gemspec and one file that defines
#   `Acme::MemoryBackend` and registers it through the hook as
#   `acme/memory`;
# - its test Gemfile, which `eval_gemfile`s the CMS's Gemfile and adds its
#   own `gemspec`, locked from a copy of the CMS's Gemfile.lock by
#   `bundle install --local` (no network: every gem is already installed);
# - its contract test, run with `BUNDLE_GEMFILE` set to that Gemfile and
#   `SEARCH_BACKEND=acme/memory`: it boots the CMS in the test environment
#   (`Bundler.require` loads the gem during the boot, before the registries
#   are filled, as in a site), requires the contract by path and runs it
#   against `SiteSearch::Backends.current`, with nothing of this suite's
#   helpers loaded.
#
# WHAT IT PROVES: the Gemfile shape resolves and boots, a gem outside the
# CMS's folder is required by the boot and its hook's backend is the one
# `SEARCH_BACKEND` chooses, and the contract needs nothing of this suite.
# WHAT IT DOES NOT: the gem's matching is its own (`MemoryBackend` hands
# every call to the CMS's `SiteSearch::Fake`, loaded by path, so the
# contract's verdict is the fake's), and its gemspec declares no dependency
# of its own, since resolving a gem the CMS's bundle does not hold would need
# the network. Neither is this suite's to prove: the contract is.
class SiteSearchBackendContractTest < ActiveSupport::TestCase
  RUN_SECONDS = 120

  GEMSPEC = <<~RUBY.freeze
    Gem::Specification.new do |spec|
      spec.name = "acme_search"
      spec.version = "0.1.0"
      spec.summary = "A search backend for ContentSpiel, for the contract's test"
      spec.authors = [ "Acme" ]
      spec.files = [ "lib/acme_search.rb" ]
      spec.require_paths = [ "lib" ]
    end
  RUBY

  BACKEND = <<~RUBY.freeze
    module Acme
      # Every call of the contract, handed to the CMS's test fake.
      class MemoryBackend
        def initialize
          require File.join(Rails.root, "test/support/site_search_fake")
          @inner = SiteSearch::Fake.new
        end

        %i[index remove prune_record clear search health].each do |name|
          define_method(name) { |*arguments, **options| @inner.public_send(name, *arguments, **options) }
        end
      end
    end

    ContentSpiel::Plugins.search_backends do |backends|
      backends.register "acme/memory", label: "Acme", backend: -> { Acme::MemoryBackend.new }
    end
  RUBY

  GEMFILE = <<~RUBY.freeze
    eval_gemfile File.join(ENV.fetch("CONTENTSPIEL_ROOT"), "Gemfile")
    gemspec
  RUBY

  CONTRACT_TEST = <<~RUBY.freeze
    ENV["RAILS_ENV"] = "test"
    require File.join(ENV.fetch("CONTENTSPIEL_ROOT"), "config/environment")
    require "active_support/test_case"
    require Rails.root.join("test/support/site_search_backend_contract").to_s

    abort "acme/memory is not the chosen backend" unless SiteSearch::Backends.current.is_a?(Acme::MemoryBackend)
    abort "the gem was loaded from inside the CMS" unless $LOADED_FEATURES.grep(/acme_search\\.rb\\z/).none? { |path| path.start_with?(Rails.root.to_s) }

    class AcmeMemoryBackendTest < ActiveSupport::TestCase
      include SiteSearchBackendContract
      include SiteSearchBackendContract::BareDocuments

      def backend = SiteSearch::Backends.current
    end

    exit(Minitest.run(%w[--seed 1]) ? 0 : 1)
  RUBY

  test "a gem with its own Gemfile and gemspec requires the contract by path and passes it with its hook's backend" do
    printed = nil
    status = nil
    Dir.mktmpdir("acme_search") do |folder|
      File.write(File.join(folder, "acme_search.gemspec"), GEMSPEC)
      FileUtils.mkdir_p(File.join(folder, "lib"))
      File.write(File.join(folder, "lib/acme_search.rb"), BACKEND)
      File.write(File.join(folder, "Gemfile"), GEMFILE)
      FileUtils.cp(Rails.root.join("Gemfile.lock"), File.join(folder, "Gemfile.lock"))
      File.write(File.join(folder, "contract_test.rb"), CONTRACT_TEST)

      env = bundle_env(folder)
      printed, status = run_in(env, "bundle", "install", "--local", "--quiet", chdir: folder)
      assert status.success?, "the gem's bundle did not resolve from the installed gems:\n#{printed}"

      printed, status = run_in(env.merge("SEARCH_BACKEND" => "acme/memory"), RbConfig.ruby, "contract_test.rb", chdir: folder)
    end

    assert status.success?, printed
    contract_tests = File.read(Rails.root.join("test/support/site_search_backend_contract.rb")).scan(/^\s+test "contract: /).size
    assert_match(/\b#{contract_tests} runs, \d+ assertions, 0 failures, 0 errors/, printed)
  end

  private

  # The gem's own bundle: its Gemfile, never frozen (its lockfile gains the
  # gem), and the CMS's install path when the CMS's bundle has one (CI's
  # `vendor/bundle`, set in the CMS's .bundle/config, which the gem's folder
  # does not see).
  def bundle_env(folder)
    env = { "CONTENTSPIEL_ROOT" => Rails.root.to_s, "BUNDLE_GEMFILE" => File.join(folder, "Gemfile"),
            "BUNDLE_FROZEN" => "false", "BUNDLE_DEPLOYMENT" => "false", "SEARCH_BACKEND" => nil,
            "BOOTSNAP_CACHE_DIR" => File.join(folder, "tmp") }
    path = Bundler.settings[:path]
    env["BUNDLE_PATH"] = File.expand_path(path, Bundler.root) if path
    env
  end

  def run_in(env, *command, chdir:)
    Bundler.with_original_env do
      Open3.popen2e(env, *command, chdir: chdir) do |input, output, thread|
        input.close
        reader = Thread.new { output.read }
        unless thread.join(RUN_SECONDS)
          Process.kill("KILL", thread.pid)
          thread.join
          flunk "#{command.join(" ")} did not finish in #{RUN_SECONDS} seconds"
        end
        [ reader.value, thread.value ]
      end
    end
  end
end
