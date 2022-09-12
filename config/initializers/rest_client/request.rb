# https://gist.github.com/bluefuton/5851093
require 'json'
require 'uri'

RestClient::Request.class_eval do
  def default_headers
    Rails.logger.info ">>>>>>>>>>>>>>>>>>> WHATSAPP_CHANNEL_URLS: #{ENV.fetch('WHATSAPP_CHANNEL_URLS', nil)}"
    @urls = JSON.parse(ENV.fetch('WHATSAPP_CHANNEL_URLS', '{}')).with_indifferent_access
    Rails.logger.info ">>>>>>>>>>>>>>>>>>> @urls: #{@urls}"
    uri = URI(@url)
    key = "#{uri.scheme}://#{uri.host}"
    Rails.logger.info ">>>>>>>>>>>>>>>>>>> @urls[#{key}]: #{@urls[key]}"
    headers = {}
    if @urls[key]
      headers.store(@urls[key][:header_name], @urls[key][:header_value])
      Rails.logger.info ">>>>>>>>>>>>>>>>>>> make_headers for #{@urls[key]} with params #{headers}"
    end
    headers
  end
end
