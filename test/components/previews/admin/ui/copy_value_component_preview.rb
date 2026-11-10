module Admin
  module Ui
    # `Admin::Ui::CopyValueComponent`, a value a person copies exactly: a
    # one-line command, a token in its block, and a long client configuration,
    # which scrolls inside its box.
    class CopyValueComponentPreview < ViewComponent::Preview
      def inline
        render Admin::Ui::CopyValueComponent.new(id: "preview-command", value: Setup::SystemCheck::SITE_ADDRESS_COMMAND,
          copy_label: "Copy command for Site address")
      end

      def block
        render Admin::Ui::CopyValueComponent.new(id: "preview-token", value: "0f3a" * 16, copy_label: "Copy token", layout: :block)
      end

      def long
        render Admin::Ui::CopyValueComponent.new(id: "preview-config", value: long_config, copy_label: "Copy the client configuration", layout: :block)
      end

      private

      # A configuration of 400 characters, with one line wider than any box.
      def long_config
        url = "https://www.a-site-with-a-rather-long-address.example/mcp"
        head = %({\n  "mcpServers": {\n    "contentspiel": {\n      "url": "#{url}",\n      "headers": { "Authorization": "Bearer )
        tail = %(" }\n    }\n  }\n})
        head + ("x" * (400 - head.size - tail.size)) + tail
      end
    end
  end
end
