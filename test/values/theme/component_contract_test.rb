require "test_helper"

# Samples of a public declaration, each named for what it gets wrong, for
# "the public contract can fail". `call` keeps them drawable, since
# test/integration/theme_pages_test.rb compiles every ViewComponent class.
class PublicContractSampleComponent < ApplicationComponent
  include Blocks::Contract

  COMMON = {
    accessibility: "A paragraph with no role, and nothing in it takes focus.",
    motion: :none,
    content_edges: %i[short],
    widths: :from_container,
    limits: [ "It is a sample." ]
  }.freeze

  contract(interface: %i[block page], words: %w[public.blocks.table.label public.blocks.note.kinds.*], **COMMON)

  def call = ""
end

class PublicContractDroppedMethodComponent < ApplicationComponent
  include Blocks::Contract
  contract(interface: %i[block], words: [], **PublicContractSampleComponent::COMMON)
  def call = ""
end

class PublicContractUnreadWordComponent < ApplicationComponent
  include Blocks::Contract
  contract(interface: %i[block page], words: %w[public.blocks.table.label public.blocks.note.kinds.* public.site.tagged], **PublicContractSampleComponent::COMMON)
  def call = ""
end

class PublicContractLeftOutWordComponent < ApplicationComponent
  include Blocks::Contract
  contract(interface: %i[block page], words: %w[public.blocks.table.label], **PublicContractSampleComponent::COMMON)
  def call = ""
end

class PublicContractNoSuchWordComponent < ApplicationComponent
  include Blocks::Contract
  contract(interface: %i[block page], words: %w[public.blocks.table.caption], **PublicContractSampleComponent::COMMON)
  def call = ""
end

# The public contract (`Blocks::Contract`) of every component a theme may
# replace, held to what the component's own files do and to the theme
# contract's line for it (`Theme::Contract.components`, which the ledger
# holds). A theme's own template is not read here: what it promises is the
# theme contract's, and its words are `string`'s and `site_string`'s guard.
class Theme::ComponentContractTest < ActiveSupport::TestCase
  # Where `Forms::PublicField` reads the words an input draws through it:
  # `field.word(:x)` is `<WORD_SCOPE>.x`, and `field.error_text(error)` one
  # of `ERROR_WORDS`.
  FIELD_WORD_SCOPE = Forms::PublicField::WORD_SCOPE
  FIELD_ERROR_WORDS = "#{Forms::PublicField::ERROR_WORDS}.*".freeze

  def public_components
    ContractLedger::COMPONENTS.keys.map { |path| path.camelize.constantize }
  end

  # The component's Ruby without its comments and its declaration, and its
  # default templates without their ERB comments.
  def own_source(klass)
    UiContract.own_source(klass).gsub(/<%#.*?%>/m, "")
  end

  # The `public.*` keys `source` reads, a read with an interpolated key as
  # its prefix and `*`, and the reads the guard cannot name.
  def words_read(source)
    found = Set.new
    unknown = []
    scopes = source.scan(/fixed_word\([^)]*?scope:\s*"([^"]+)"/).flatten.uniq
    text = source.dup

    text.gsub!(/(?<![\w.])string\(:(\w+)/) do
      scopes.one? ? found << "#{scopes.first}.#{$1}" : unknown << "string(:#{$1}) with #{scopes.size} scopes in its fixed_word"
      ""
    end
    text.gsub!(/fixed_word\(:(\w+)[^)]*?scope:\s*"([^"]+)"/) { found << "#{$2}.#{$1}"; "" }
    text.gsub!(/fixed_word\([^)]*?scope:\s*"[^"]+"/, "")
    text.gsub!(/(?<![\w.])site_string\(:(\w+)/) { found << "public.site.#{$1}"; "" }
    text.gsub!(/\bfield\.word\(:(\w+)/) { found << "#{FIELD_WORD_SCOPE}.#{$1}"; "" }
    text.gsub!(/\bfield\.error_text\(/) { found << FIELD_ERROR_WORDS; "" }
    text.gsub!(/PublicStrings\.read\("([^"]*)"/) do
      key = $1
      if !key.start_with?("public.") then unknown << "PublicStrings.read(\"#{key}\")"
      elsif key.include?('#{') then found << "#{key[/\A[^#]*/]}*"
      else found << key
      end
      ""
    end
    text.scan(/["']public\.[\w.\#{}]*["']/) { |literal| unknown << literal }
    [ found, unknown ]
  end

  def assert_public_contract_declared(klass)
    assert klass.include?(Blocks::Contract), "#{klass.name} does not include Blocks::Contract"
    assert_not_nil klass.contract, "#{klass.name} does not declare its contract"
    klass.contract
  end

  def assert_public_interface(klass, line: Theme::Contract.components[Theme::Contract.path_of(klass)])
    contract = assert_public_contract_declared(klass)
    assert_not_nil line, "#{klass.name} is no component a theme may replace (Theme::Contract.components has no #{Theme::Contract.path_of(klass)})"
    declared = contract.interface.map(&:to_s)
    assert_equal line, declared,
      "#{klass.name}'s contract interface is not its line in the theme contract: it leaves out #{(line - declared).inspect} " \
      "and adds #{(declared - line).inspect} (Theme::Contract.components, the ledger's line)"
  end

  def assert_public_words(klass, source: own_source(klass))
    contract = assert_public_contract_declared(klass)
    found, unknown = words_read(source)
    declared = contract.words.to_set
    assert_empty unknown, "#{klass.name} reads a public word the guard cannot name: #{unknown.join(', ')}"
    assert_empty found - declared, "#{klass.name}'s files read #{(found - declared).to_a.inspect}, which its contract's words leave out"
    assert_empty declared - found, "#{klass.name}'s contract's words name #{(declared - found).to_a.inspect}, which its files do not read"

    contract.words.each do |word|
      if word.end_with?(".*")
        value = I18n.t(word.delete_suffix(".*"), locale: :en, default: nil)
        assert value.is_a?(Hash) && value.any?, "#{klass.name}'s word #{word} names no keys in config/locales/public.en.yml"
      else
        assert I18n.exists?(word, :en), "#{klass.name}'s word #{word} is not in config/locales/public.en.yml"
      end
    end
  end

  test "every built-in component a theme may replace declares the public contract" do
    assert_equal 18, public_components.size, "the ledger's components: nine blocks, five form inputs, four post components"
    public_components.each { |klass| assert_public_contract_declared(klass) }
  end

  test "a component that declares the public contract is one a theme may replace" do
    declaring = Dir[Rails.root.join("app/components/{blocks,posts}/**/*.rb")].select { |file| File.read(file).match?(/^\s*include Blocks::Contract\b/) }
    paths = declaring.map { |file| file.delete_prefix("#{Rails.root.join('app/components')}/").delete_suffix(".rb") }
    assert_equal ContractLedger::COMPONENTS.size, paths.size
    paths.each { |path| assert_includes Theme::Contract.components.keys, path, "#{path} declares the public contract and is no component a theme may replace" }
  end

  test "a public component's interface is its line in the theme contract" do
    public_components.each { |klass| assert_public_interface(klass) }
  end

  test "a public component's words are the public keys its own files read, and each exists in English" do
    public_components.each { |klass| assert_public_words(klass) }
  end

  test "the public contract can fail" do
    source = '<%= PublicStrings.read("public.blocks.table.label") %> PublicStrings.read("public.blocks.note.kinds.#{kind}")'
    assert_public_interface(PublicContractSampleComponent, line: %w[block page])
    assert_public_words(PublicContractSampleComponent, source: source)

    failure = assert_raises(Minitest::Assertion) { assert_public_interface(PublicContractDroppedMethodComponent, line: %w[block page]) }
    assert_match "PublicContractDroppedMethodComponent's contract interface", failure.message
    assert_match '["page"]', failure.message

    failure = assert_raises(Minitest::Assertion) { assert_public_interface(PublicContractSampleComponent, line: nil) }
    assert_match "no component a theme may replace", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_public_words(PublicContractUnreadWordComponent, source: source) }
    assert_match "public.site.tagged", failure.message
    assert_match "which its files do not read", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_public_words(PublicContractLeftOutWordComponent, source: source) }
    assert_match "public.blocks.note.kinds.*", failure.message
    assert_match "which its contract's words leave out", failure.message

    failure = assert_raises(Minitest::Assertion) { assert_public_words(PublicContractNoSuchWordComponent, source: 'PublicStrings.read("public.blocks.table.caption")') }
    assert_match "is not in config/locales/public.en.yml", failure.message

    # The empty declaration fails where the files read a word.
    failure = assert_raises(Minitest::Assertion) { assert_public_words(PublicContractDroppedMethodComponent, source: source) }
    assert_match "public.blocks.table.label", failure.message

    # A read the guard cannot name is reported, not passed over.
    failure = assert_raises(Minitest::Assertion) { assert_public_words(PublicContractDroppedMethodComponent, source: 'I18n.t("public.site.tagged")') }
    assert_match "the guard cannot name", failure.message

    # string(:x) is named by its file's fixed_word scope.
    found, unknown = words_read('string(:copy) site_string(:tagged) def string(key) = fixed_word(key, scope: "public.blocks.code", owner: "x")')
    assert_equal %w[public.blocks.code.copy public.site.tagged].to_set, found
    assert_empty unknown

    failure = assert_raises(Minitest::Assertion) { assert_public_contract_declared(Class.new(ApplicationComponent) { def self.name = "PublicContractBareComponent" }) }
    assert_match "PublicContractBareComponent does not include Blocks::Contract", failure.message
  end

  test "a public declaration's words are public keys, a prefix ending in .*" do
    error = assert_raises(ArgumentError) do
      Class.new(ApplicationComponent) do
        def self.name = "PublicContractAdminWordComponent"
        include Blocks::Contract
        contract(interface: %i[block], words: %w[admin.components.ui.button.close], **PublicContractSampleComponent::COMMON)
      end
    end
    assert_match "PublicContractAdminWordComponent's contract: words", error.message

    error = assert_raises(ArgumentError) do
      Class.new(ApplicationComponent) do
        def self.name = "PublicContractNoWordsComponent"
        include Blocks::Contract
        contract(interface: %i[block], **PublicContractSampleComponent::COMMON)
      end
    end
    assert_match "missing words", error.message
  end

  test "the Studio and the public contract share only the common declaration" do
    shared = Blocks::Contract::Declaration.members & Admin::Ui::Contract::Declaration.members
    assert_equal ComponentContract::COMMON.sort, shared.sort
    assert_equal [ :words ], Blocks::Contract::Declaration.members - ComponentContract::COMMON

    [ Blocks::Contract, Admin::Ui::Contract ].each do |mod|
      assert_kind_of Module, mod
      assert_not_kind_of Class, mod
    end
    assert_not Blocks::Contract.include?(Admin::Ui::Contract)
    assert_not Admin::Ui::Contract.include?(Blocks::Contract)
    public_components.each { |klass| assert_not klass.include?(Admin::Ui::Contract), "#{klass.name} includes the Studio contract" }
  end
end
