require 'test_helper'

class OEmbedTest < Test::Unit::TestCase
  context "oembed" do
    setup do
      @oembed = Vimeo::OEmbed.new
    end

    should "be able to get the embed information" do
      stub_custom_get("/api/oembed.json?url=http%3A//vimeo.com/7100569", "o_embed/get_info.json")
      response = @oembed.get_info("7100569")
      assert_equal 'video', response['type']
    end
  end
end
