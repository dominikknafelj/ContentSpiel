module ContentSpiel
  # The test database's name for a working folder (config/database.yml reads
  # it while the configuration is loaded, before autoloading, so it is plain
  # Ruby required by path). `ContentSpiel`, and CI's checkout of the same
  # name, use content_spiel_test; a worktree beside it named
  # `ContentSpiel-note` uses content_spiel_test_note. Two worktrees that
  # shared one test database emptied each other's tables in the middle of a
  # run. Development stays one database for every folder, on purpose: it is
  # the content a person looks at.
  module TestDatabase
    BASE = "content_spiel_test".freeze

    def self.name_for(root)
      folder = File.basename(root.to_s).delete_prefix("ContentSpiel").delete_prefix("-")
      suffix = folder.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
      suffix.empty? ? BASE : "#{BASE}_#{suffix}"
    end
  end
end
