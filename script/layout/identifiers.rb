# Rewrites Stimulus identifiers after a controller moved. Usage:
#   ruby script/layout/identifiers.rb admin--notes-live=admin--notes--live admin--dialog=admin--ui--dialog
# Idempotent. Deleted in the plan's last task.
require "pathname"

pairs = ARGV.to_h { |arg| arg.split("=", 2) }
abort "usage: identifiers.rb OLD=NEW ..." if pairs.empty? || pairs.any? { |old, new| new.nil? || old.empty? }

ROOT = Pathname(__dir__).join("../..").expand_path
ALL_OLD = Dir[ROOT.join("app/javascript/controllers/admin/*_controller.js")].map { |f| "admin--" + File.basename(f, "_controller.js").tr("_", "-") } | pairs.keys
FILES = Dir[ROOT.join("{app,test,docs,config/locales}/**/*.{rb,erb,js,css,yml,md}")] + [ ROOT.join("CLAUDE.md").to_s ]
# A run of the old one-level form, matched whole (the atomic group forbids a shorter match). A run followed by "--" is already in the new form: leave it.
TOKEN = /(?<![a-z0-9-])(?>admin--[a-z0-9]+(?:-[a-z0-9]+)*)(?!--)/

review = []
FILES.each do |path|
  text = File.read(path)
  changed = text.gsub(TOKEN) do |token|
    owners = ALL_OLD.select { |id| token == id || token.start_with?("#{id}-") }
    owner = owners.max_by(&:length)
    next token unless owner && pairs.key?(owner)

    review << "#{Pathname(path).relative_path_from(ROOT)}: #{token} (could also be #{(owners - [ owner ]).join(', ')})" if owners.size > 1
    pairs.fetch(owner) + token.delete_prefix(owner)
  end
  next if changed == text

  File.write(path, changed)
  puts Pathname(path).relative_path_from(ROOT)
end
puts "REVIEW:", review.uniq
