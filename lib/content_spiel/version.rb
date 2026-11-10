# The CMS's release number and the name of its image (no tag). Plain Ruby,
# required from config/application.rb beside the other early lib/ files, so
# anything that reads it (a task, an initializer, a workflow) can before
# autoloading is set up; not reloaded in development.
# VERSION 0.0.0 means never released: the first `release:prepare[0.1.0]` is the
# first release.
module ContentSpiel
  VERSION = "0.1.0"
  IMAGE = "ghcr.io/dominikknafelj/content_spiel"
end
