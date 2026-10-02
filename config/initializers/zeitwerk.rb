# `app/models/ai.rb` defines `AI`, not `Ai` (translation helpers spec §6):
# the acronym is how the spec, the code and every reader spell it. Only the
# autoloaders' own inflector learns it -- not `ActiveSupport::Inflector`,
# where an "AI" acronym would also change how every unrelated
# `"..._ai_..."` string camelizes (`"ai_provider".camelize`, column names
# turned into constants, ...). Zeitwerk inflects by file and directory
# basename, so this covers `app/models/ai/`, `app/services/ai/`, ... alike.
#
# Never add an `Admin::AI`/`Admin::Ai` module (global constraints): inside
# `module Admin`, it would shadow `::AI` for every admin controller and
# component.
Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("ai" => "AI")
end
