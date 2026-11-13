require "test_helper"

# The guard for the naming trap inside the `SignIn` domain.
#
# Ruby resolves a bare constant through the lexical scope first: inside
# `module SignIn ... end` (every class of the sign-in domain) a bare `Session`
# is looked up as `SignIn::Session` before the top-level model is ever tried.
# So a module or class named `SignIn::Session`, `SignIn::Passkey` or
# `SignIn::User` shadows the model for every such reference, in files that did
# not change at all, and the failure is a NameError or, worse, the wrong
# constant. That is why the sub-namespaces are the plurals `Sessions` and
# `Passkeys`, and `RecoveryCodes`, never `Session`, `Passkey` or `RecoveryCode`.
#
# The names under `SignIn`, at EVERY level (not only `SignIn::X` but
# `SignIn::Sso::X`), are DERIVED from the `sign_in/` directories of
# every autoload root of the application (`Rails.autoloaders.main.dirs`, so a
# new layer folder is read without an edit here), never listed, and compared
# with `TopLevelNames` (app/values/top_level_names.rb), the same list
# the Admin guard and a gem's owner are refused by. The domain is two levels
# deep and no deeper: `SignIn::Passkeys::Add`, never `SignIn::Passkeys::X::Add`.
class SignInNamespaceShadowTest < ActiveSupport::TestCase
  # The application's own autoload roots, as absolute paths; a gem's are not
  # the application's.
  ROOTS = Rails.autoloaders.main.dirs.select { |dir| dir.start_with?("#{Rails.root}/") }.freeze

  # A name under `SignIn` that is also a top-level constant, with the reason it
  # is safe. EMPTY today, and it should stay that way: an entry here means
  # every bare reference to that top-level constant inside `module SignIn`
  # must be written `::Name`, for ever. Add one only with that reason written
  # beside it.
  ALLOWED = {}.freeze

  # Every name under `SignIn`, at every level, as Zeitwerk names it: the
  # directories and files of `sign_in/` and of every folder below it, in every
  # layer. Only the LAST segment matters (`SignIn::Sso::Session` is "Session"),
  # because Ruby looks a bare constant up through the lexical scopes of
  # `module SignIn; module Sso`, so a `Session` at any level hides the model for
  # the code written inside that level and the ones under it.
  def self.children
    inflector = Rails.autoloaders.main.inflector
    ROOTS.flat_map do |root|
      Dir[File.join(root, "sign_in", "**", "*")].filter_map do |path|
        next unless File.directory?(path) || path.end_with?(".rb")

        inflector.camelize(File.basename(path, ".rb"), path)
      end
    end.uniq.sort
  end

  def self.top_level = TopLevelNames.all | TopLevelNames.owners

  test "the list is derived from the directories" do
    names = self.class.children
    %w[Proof OutsideCall SpentChallenge Outcome Protection Password Passkeys RecoveryCodes Sso Sessions Rules Methods Throttle Add RecheckJob].each { |name| assert_includes names, name }
    assert_operator names.size, :>=, 5
  end

  test "no name under SignIn, at any level, is a top-level constant's" do
    offenders = (self.class.children & self.class.top_level) - ALLOWED.keys
    assert_empty offenders, -> { <<~MESSAGE }
      A constant named #{offenders.first} exists under SignIn (at some level), and #{offenders.first} is also a top-level constant. Every bare
      `#{offenders.first}` inside `module SignIn` would now mean SignIn::#{offenders.first}, not the model
      or domain of that name, and fail without the file having changed.
      Name it in the plural or after what it does, as Sessions and Passkeys are
      (SignIn::#{offenders.first}s, not SignIn::#{offenders.first}).
      Every offender: #{offenders.join(", ")}
    MESSAGE

    ALLOWED.each do |name, reason|
      assert_includes self.class.children, name, "#{name} is allow-listed but nothing under SignIn has that name: remove the entry"
      assert_operator reason.to_s.length, :>, 20, "say why SignIn::#{name} is safe"
    end
  end

  # The lookup itself, the way a file under `module SignIn` does it: a string
  # evaluated in `SignIn` has `SignIn` as its lexical scope.
  test "a bare reference from inside SignIn reaches the top-level constant" do
    Rails.application.eager_load!
    TopLevelNames.all.each do |name|
      next unless Object.const_defined?(name, false)

      assert_same Object.const_get(name), SignIn.module_eval(name), "a bare #{name} inside module SignIn is not the top-level #{name}"
    end
  end

  test "nothing is deeper than two levels" do
    deeper = ROOTS.flat_map { |root| Dir[File.join(root, "sign_in/*/*/")] }
    assert_empty deeper, "The sign-in domain is two levels deep (SignIn::Passkeys::Add); a third level is a directory: #{deeper.join(", ")}. A class nested inside a file (Throttle::Trip) is not a level."
  end
end
