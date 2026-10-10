# Rewrites a component's class name after it moved. Usage:
#   ruby script/layout/constants.rb Admin::ButtonComponent=Admin::Ui::ButtonComponent
# Rewrites the full name everywhere, and the bare name (`ButtonComponent`,
# as code inside `module Admin` writes it) to the new name without `Admin::`.
# Idempotent. Deleted in the plan's last task.
require "pathname"

pairs = ARGV.to_h { |arg| arg.split("=", 2) }
abort "usage: constants.rb Old::Name=New::Name ..." if pairs.empty?

ROOT = Pathname(__dir__).join("../..").expand_path
FILES = Dir[ROOT.join("{app,test,docs,config,lib}/**/*.{rb,erb,yml,md,rake}")] + [ ROOT.join("CLAUDE.md").to_s ]
# Specs and plans are historical records and quote old names on purpose; built CSS is
# git-ignored; the guard test holds sample strings that must stay as written.
EXCLUDED = %w[docs/superpowers docs/product docs/architecture app/assets/builds test/lib/source_layout_test.rb test/lib/layout_tools_test.rb].map { |path| ROOT.join(path).to_s }
FILES.reject! { |path| EXCLUDED.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") } }
review = []
FILES.each do |path|
  text = File.read(path)
  changed = pairs.reduce(text) do |body, (old, new)|
    bare_old = old.delete_prefix("Admin::")
    bare_new = new.delete_prefix("Admin::")
    body = body.gsub(/(?<![\w:])#{Regexp.escape(old)}\b/, new)
    # Bare, and not already qualified: `ButtonComponent.new` inside `module Admin`.
    # A definition (`class ButtonComponent`, `module Foo`) keeps its name: it is nested by hand.
    body.lines.each_with_index.map do |line, index|
      line.gsub(/(?<![\w:])#{Regexp.escape(bare_old)}\b/) do
        next bare_old if $`.match?(/\b(?:class|module)\s+\z/)

        review << "#{Pathname(path).relative_path_from(ROOT)}:#{index + 1}: #{line.strip[0, 160]}"
        bare_new
      end
    end.join
  end
  next if changed == text

  File.write(path, changed)
  puts Pathname(path).relative_path_from(ROOT)
end
puts "REVIEW:", review.uniq
