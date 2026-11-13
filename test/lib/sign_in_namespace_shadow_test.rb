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
# The names under `SignIn` are DERIVED from the directories (`app/models/
# sign_in/`, `app/services/sign_in/`, `app/jobs/sign_in/`), never listed, and
# compared with `TopLevelNames` (app/values/top_level_names.rb), the same list
# the Admin guard and a gem's owner are refused by. The domain is two levels
# deep and no deeper: `SignIn::Passkeys::Add`, never `SignIn::Passkeys::X::Add`.
class SignInNamespaceShadowTest < ActiveSupport::TestCase
  ROOTS = %w[app/models app/services app/jobs].freeze

  # A name under `SignIn` that is also a top-level constant, with the reason it
  # is safe. EMPTY today, and it should stay that way: an entry here means
  # every bare reference to that top-level constant inside `module SignIn`
  # must be written `::Name`, for ever. Add one only with that reason written
  # beside it.
  ALLOWED = {}.freeze

  # The directories and files directly under `SignIn`, as Zeitwerk names them.
  def self.children
    inflector = Rails.autoloaders.main.inflector
    ROOTS.flat_map do |root|
      Dir[Rails.root.join(root, "sign_in", "*")].map do |path|
        inflector.camelize(File.basename(path, ".rb"), path)
      end
    end.uniq.sort
  end

  def self.top_level = TopLevelNames.all | TopLevelNames.owners

  test "the list is derived from the directories" do
    names = self.class.children
    %w[Proof OutsideCall SpentChallenge Outcome].each { |name| assert_includes names, name }
    assert_operator names.size, :>=, 5
  end

  test "no name under SignIn is a top-level constant's" do
    offenders = (self.class.children & self.class.top_level) - ALLOWED.keys
    assert_empty offenders, -> { <<~MESSAGE }
      SignIn::#{offenders.first} exists, and #{offenders.first} is also a top-level constant. Every bare
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
    deeper = ROOTS.flat_map { |root| Dir[Rails.root.join(root, "sign_in/*/*/")] }
    assert_empty deeper, "The sign-in domain is two levels deep (SignIn::Passkeys::Add, plan decision 2); a third level is a directory: #{deeper.join(", ")}. A class nested inside a file (Throttle::Trip) is not a level."
  end
end
