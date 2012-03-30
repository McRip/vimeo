module Vimeo
  class OEmbed
    include HTTParty

    def get_info(video_id, params=nil)
      query_url = "http://vimeo.com/api/oembed.json?url=http%3A//vimeo.com/#{video_id}"
      query_url += "&"+params.to_query if params
      HTTParty::get(query_url)
    end
  end
end
