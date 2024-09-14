class Channels::NotificaMe::TemplatesSyncSchedulerJob < ApplicationJob
  queue_as :low

  def perform
    Channel::NotificaMe
      .where(
        '(message_templates_last_updated <= ? OR message_templates_last_updated IS NULL) AND notifica_me_type = ?',
        3.hours.ago,
        'whatsapp_business_account'
      )
      .order(Arel.sql('message_templates_last_updated IS NULL DESC, message_templates_last_updated ASC'))
      .limit(Limits::BULK_EXTERNAL_HTTP_CALLS_LIMIT)
      .each do |channel|
      Channels::NotificaMe::TemplatesSyncJob.perform_later(channel)
    end
  end
end
