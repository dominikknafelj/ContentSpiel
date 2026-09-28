namespace :rich_text do
  # Design spec §5 -- see `RichText::ActionTextImport` for what it does and
  # when to run it (between the two halves of `db:migrate` on an install
  # that still has ActionText bodies).
  desc "Convert every ActionText body into its record's per-locale JSON document (idempotent)"
  task migrate_from_action_text: :environment do
    RichText::ActionTextImport.new.run
  end
end
