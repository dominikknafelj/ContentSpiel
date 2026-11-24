module ContentSpiel
  # The site's backup accessory in Kamal's configuration: the block
  # `contentspiel new` writes, commented, into a new site's config/deploy.yml
  # (lib/site_template/config/deploy.yml.tt) and the block `contentspiel
  # upgrade` prints for a site whose deploy.yml has none. One source, so a
  # new site and an upgraded one run the same accessory.
  #
  #   ContentSpiel::BackupAccessory.block(service: "my-site", volume: "my_site_storage",
  #                                       cms_image: ContentSpiel::IMAGE, commented: true)
  #
  # The block holds Kamal's own ERB, `<%= pin %>` and `<%= server_ip %>`,
  # which the top of every template-made deploy.yml defines; the generator
  # inserts it as a value, so its ERB reaches deploy.yml as written. It
  # starts and ends with BEGIN_MARK and END_MARK, comment lines in both forms,
  # by which a test and `upgrade` find it. Commented, each line between the
  # marks is `  # ` and the line after its first two spaces, so an editor's
  # "uncomment" (which takes out "# ") gives the uncommented block back.
  #
  # `<endpoint>` and `<bucket>` are not `<your-…>` placeholders on purpose:
  # the README's grep for unfilled placeholders stays quiet for a site that
  # does not use backups. A site that does fills them in step 4.4.
  #
  # Not autoloaded (config/application.rb tells Zeitwerk to leave it alone):
  # site_generator.rb requires it by path before the application starts, as
  # upgrade.rb does. Plain Ruby, no library.
  module BackupAccessory
    BEGIN_MARK = "# The backup accessory".freeze
    END_MARK = "# End of the backup accessory".freeze

    # The accessory's secrets that only it has: the site's secrets example
    # lists them commented (`secrets_example`). POSTGRES_PASSWORD, which it
    # names too, is the database accessory's and listed already.
    SECRETS = %w[RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY].freeze

    # The YAML of the accessory, indented to sit under `accessories:`, with
    # no newline after its last line.
    def self.block(service:, volume:, cms_image:, commented:)
      lines = <<~YAML.lines(chomp: true)
        backup:
          # The CMS image at this site's pin: backups need no theme. After a
          # deploy that moves the pin: kamal accessory reboot backup
          image: #{cms_image}:<%= pin %>
          host: <%= server_ip %>
          cmd: bin/backup schedule
          # One CPU at most, so a backup can never take the whole server.
          options:
            cpus: 1
          env:
            clear:
              PGHOST: #{service}-db
              BACKUP_SITE: #{service}
              BACKUP_REPOSITORY: s3:https://<endpoint>/<bucket>/#{service}
              AWS_DEFAULT_REGION: auto
              # BACKUP_HOUR: 3
              # Hours between runs from BACKUP_HOUR: 1, 2, 3, 4, 6, 8, 12 or 24.
              # BACKUP_EVERY: 24
            secret:
              - POSTGRES_PASSWORD
              - RESTIC_PASSWORD
              - AWS_ACCESS_KEY_ID
              - AWS_SECRET_ACCESS_KEY
          volumes:
            # The files volume, read and write: bin/backup reads it and writes
            # only storage/backup/status.json, which System status reads.
            - #{volume}:/rails/storage
      YAML
      body = lines.map { |line| commented ? "  # #{line}" : "  #{line}" }
      [ "  #{BEGIN_MARK}", *body, "  #{END_MARK}" ].join("\n")
    end

    # The secrets example's lines for the three, commented: they are
    # uncommented with the accessory. No newline after the last line.
    def self.secrets_example
      <<~TEXT.chomp
        # Backups (README.md, step 4.4): uncomment these three with the backup
        # accessory in config/deploy.yml.
        # The backup repository's encryption password.
        # Made with: openssl rand -base64 32
        # Keep it in your password manager: losing it loses every backup.
        # RESTIC_PASSWORD=$RESTIC_PASSWORD
        # The bucket's key pair, from the provider (README.md, step 4.4).
        # AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
        # AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
      TEXT
    end
  end
end
