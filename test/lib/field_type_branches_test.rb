require "test_helper"
require "ripper"

# A field type is one entry of `ContentModel::FieldTypes` and one input under
# `Admin::Fields`, and nothing else asks which type a field is by its name:
# a cast, an option rule, a validation, whether it is offered to AI
# translation, how the audit log records it and how it reads where it cannot
# be edited are all the type's own answers. Before the registry the ten
# types' behaviour was spread over seven core files, and a new type meant a
# branch in each.
#
# A source grep of `app/` and `lib/` (comments stripped), for every scalar
# type the registry holds: `type == :name`, `type != :name`, `when :name`
# inside a `case field.type` or `case type`, `include?(field.type)`, a
# literal list of names asked `include?(type)`, and the two hand lists the
# registry replaced, `SCALAR_TYPES` and `TRANSLATABLE_TYPES`. The group types
# (`group`, `groups`) are not scalar and not in it.
class FieldTypeBranchesTest < ActiveSupport::TestCase
  ROOTS = %w[app lib].freeze

  ALLOWED = [
    { path: "app/models/content_model/field_types.rb", pattern: :any,
      reason: "the registry itself: each type's answers are written here, under its name, and a type's own rules may name another type (a string's `placeholder_from:` names a select)" },
    { path: "app/models/rich_text/document.rb", pattern: :when,
      reason: "`attribute_type_matches?` cases on a rich-text node attribute's type (`RichText::Schema::Attribute`), whose names `:string`, `:integer` and `:boolean` are not field types" },
    { path: "app/models/rich_text/schema.rb", pattern: :compare,
      reason: "`coerce_directive_value` compares a rich-text node attribute's type with `:integer`; it is no field type and never a field's" },
    { path: "app/components/admin/ui/field_component.rb", pattern: :constant,
      reason: "`TRANSLATABLE_TYPES` is read by its name from outside (a component test); its value is derived from the registry, never written as a list, and nothing in app branches on it" }
  ].freeze

  # The form registry's types (`Forms::FieldTypes`) are named by Strings, in a
  # compare (`type == "choice"`, `field.type_name != "checkbox"`) or in a
  # `case` on the type; `Forms::BuiltInFieldTypes` is where they are named,
  # and nothing else asks which form field type a field is by its name.
  def self.form_patterns(names)
    alternatives = names.map { |name| Regexp.escape(name.to_s) }.join("|")
    {
      form_compare: /\b(?:type|type_name)\s*[!=]=\s*["'](?:#{alternatives})["']/,
      form_include: /%w\[[^\]]*\b(?:#{alternatives})\b[^\]]*\]\.include\?\(\s*(?:field\.)?(?:type|type_name)\s*\)/,
      form_when: /^[ \t]*when\b[^\n]*["'](?:#{alternatives})["']/
    }
  end

  def self.patterns(names)
    alternatives = names.map { |name| Regexp.escape(name.to_s) }.join("|")
    {
      compare: /\btype\s*[!=]=\s*:(?:#{alternatives})\b/,
      include: /include\?\(\s*field\.type\s*\)|%i\[[^\]]*\b(?:#{alternatives})\b[^\]]*\]\.include\?\(\s*(?:field\.)?type\s*\)/,
      constant: /\b(?:SCALAR_TYPES|TRANSLATABLE_TYPES)\b/,
      when: /^[ \t]*when\b[^\n]*:(?:#{alternatives})\b/
    }
  end

  # A path and its offences, as hashes naming the path, the line, the pattern
  # and the matched text.
  def self.offences(path, source, names: ContentModel::FieldTypes.names, form_names: Forms::FieldTypes.names)
    code = path.to_s.end_with?(".erb") ? source.gsub(/<%#.*?%>/m) { |comment| comment.gsub(/[^\n]/, "") } : without_comments(source)
    relative = path.to_s.delete_prefix("#{Rails.root}/")

    patterns(names).merge(form_patterns(form_names)).flat_map do |name, pattern|
      haystacks = %i[when form_when].include?(name) ? case_bodies(code) : [ [ code, 0 ] ]
      haystacks.flat_map do |text, offset|
        text.to_enum(:scan, pattern).map { Regexp.last_match }.map do |match|
          start = offset + match.begin(0)
          { path: relative, line: code[0...start].count("\n") + 1, pattern: name, text: match[0].strip }
        end
      end
    end
  end

  # Each `case field.type` / `case type` with its body, up to the `end` at
  # the case's own indentation, and where in the source it begins.
  def self.case_bodies(code)
    code.to_enum(:scan, /^([ \t]*)(?:[^\n]*?=\s*)?case\s+(?:field\.)?type[ \t]*$/).map { Regexp.last_match }.map do |match|
      rest = code[match.end(0)..]
      finish = rest =~ /^#{match[1]}end\b/
      [ rest[0...(finish || rest.length)], match.end(0) ]
    end
  end

  # The source with every comment blanked and the line breaks kept, so a line
  # number still names the line (as `DependencyDirectionTest` strips them).
  def self.without_comments(source)
    Ripper.lex(source).map do |(_position, type, token, _state)|
      type.to_s.match?(/\Aon_(comment|embdoc)/) ? token.gsub(/[^\n]/, "") : token
    end.join
  end

  def self.allowed?(offence, entry)
    entry[:path] == offence[:path] && (entry[:pattern] == :any || entry[:pattern] == offence[:pattern])
  end

  def sources = ROOTS.flat_map { |root| Dir[Rails.root.join(root, "**/*.{rb,erb}")] }.sort

  def all_offences = sources.flat_map { |path| self.class.offences(path, File.read(path)) }

  test "the guard is looking at the code" do
    assert_operator sources.size, :>, 100, "this guard is looking at too little"
    assert_operator ContentModel::FieldTypes.names.size, :>=, 10
    assert_equal 5, Forms::FieldTypes.names.size
  end

  test "no file outside the field-type registry branches on a scalar field type's name" do
    offending = all_offences.reject { |offence| ALLOWED.any? { |entry| self.class.allowed?(offence, entry) } }

    assert_empty offending.map { |offence| "#{offence[:path]}:#{offence[:line]}: #{offence[:pattern]}: #{offence[:text]}" },
      "a file branches on a field type's name. Give the type the answer (ContentModel::FieldTypes) or its input " \
      "(Admin::Fields::<Type>Field) instead; allow it in ALLOWED only with its reason."
  end

  test "every allowance still matches something, and says why" do
    offences = all_offences
    stale = ALLOWED.reject { |entry| offences.any? { |offence| self.class.allowed?(offence, entry) } }

    assert_empty stale.map { |entry| "#{entry[:path]} (#{entry[:pattern]})" }, "an ALLOWED entry no longer matches anything: delete it"
    ALLOWED.each { |entry| assert_operator entry[:reason].length, :>, 40, "#{entry[:path]} needs its reason written out" }
  end

  test "the patterns match what they should, and nothing that only looks like it" do
    flagged = ->(source, path = "app/models/x.rb") { self.class.offences(path, source, names: %i[string date]).map { |offence| offence[:pattern] } }

    assert_equal [ :compare ], flagged.call("x if field.type == :date")
    assert_equal [ :compare ], flagged.call("x unless type != :string")
    assert_equal [ :include ], flagged.call("LIST.include?(field.type)")
    assert_equal [ :include ], flagged.call("%i[date tag].include?(type)")
    assert_equal [ :constant ], flagged.call("SCALAR_TYPES + GROUP_TYPES")
    assert_equal [ :when ], flagged.call("case field.type\nwhen :date then 1\nend\n")
    assert_equal [ :when ], flagged.call("  x = case type\n  when :string, :text then 1\n  end\n")
    assert_equal [ :compare ], flagged.call("<% if field.type == :date %>", "app/components/x.html.erb")

    form = ->(source) { self.class.offences("app/models/x.rb", source, names: [], form_names: %w[choice checkbox]).map { |offence| offence[:pattern] } }
    assert_equal [ :form_compare ], form.call(%(x if field.type == "choice"))
    assert_equal [ :form_compare ], form.call(%(x unless type_name != 'checkbox'))
    assert_equal [ :form_include ], form.call(%(%w[choice checkbox].include?(type_name)))
    assert_equal [ :form_when ], form.call("case field.type\nwhen \"choice\" then 1\nend\n")
    assert_empty form.call(%(x if field.type == "short_text"))
    assert_empty form.call(%(# x if type == "choice"))
    assert_empty form.call("case node.type\nwhen \"choice\" then 1\nend\n")

    assert_empty flagged.call("# field.type == :date, SCALAR_TYPES\nx = 1 # when :date")
    assert_empty flagged.call("<%# field.type == :date %>", "app/components/x.html.erb")
    assert_empty flagged.call("case node.type\nwhen :string then 1\nend\n")
    assert_empty flagged.call("case field.type\nwhen :groups then 1\nend\nwhen :date")
    assert_empty flagged.call("GROUP_TYPES.include?(type)")
    assert_empty flagged.call("x if field.type == :group")
  end
end
