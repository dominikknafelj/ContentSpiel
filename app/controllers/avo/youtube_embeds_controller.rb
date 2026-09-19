# Backs the Trix paste-to-embed handler (design spec section 8): given a
# pasted URL, finds or creates the YoutubeEmbed it names and hands back the
# signed global id the editor's JS needs to insert an
# <action-text-attachment>. Inherits Avo::ApplicationController's session
# gate, same as every other /avo route -- this is part of the admin, not a
# public endpoint.
class Avo::YoutubeEmbedsController < Avo::ApplicationController
  def create
    embed = YoutubeEmbed.find_or_create_from_url(params[:url])

    if embed
      render json: { sgid: embed.attachable_sgid, content_type: embed.attachable_content_type }
    else
      render json: { error: "Not a recognizable YouTube video URL" }, status: :unprocessable_entity
    end
  end
end
