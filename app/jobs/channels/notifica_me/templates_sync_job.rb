class Channels::NotificaMe::TemplatesSyncJob < ApplicationJob
  queue_as :low

  def perform(channel)
    channel.sync_templates
  end
end
